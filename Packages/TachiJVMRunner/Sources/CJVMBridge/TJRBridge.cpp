#include "TJRBridge.h"
#include "jni.h"

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <new>
#include <string>
#include <vector>

#if defined(__APPLE__)
#include <dlfcn.h>
#endif

struct TJRRuntime {
    JavaVM *vm;
    std::vector<void *> library_handles;
};

namespace {

char *copy_string(const std::string &value) {
    char *result = static_cast<char *>(std::malloc(value.size() + 1));
    if (result == nullptr) {
        return nullptr;
    }
    std::memcpy(result, value.c_str(), value.size() + 1);
    return result;
}

void set_error(char **destination, const std::string &message) {
    if (destination != nullptr) {
        *destination = copy_string(message);
    }
}

#if defined(__APPLE__)
void *load_framework(
    const std::string &directory,
    const std::string &name,
    std::string &error
) {
    const std::string path = directory + "/" + name + ".framework/" + name;
    void *handle = dlopen(path.c_str(), RTLD_NOW | RTLD_GLOBAL);
    if (handle == nullptr) {
        const char *loader_error = dlerror();
        error = "Unable to load " + path;
        if (loader_error != nullptr) {
            error += ": ";
            error += loader_error;
        }
    }
    return handle;
}
#endif

std::string java_exception_message(JNIEnv *environment) {
    jthrowable exception = environment->ExceptionOccurred();
    if (exception == nullptr) {
        return "Java raised an unknown exception";
    }
    environment->ExceptionClear();

    std::string message = "Java exception";
    jclass throwable_class = environment->FindClass("java/lang/Throwable");
    if (throwable_class == nullptr) {
        environment->ExceptionClear();
        return message;
    }

    jmethodID to_string = environment->GetMethodID(
        throwable_class,
        "toString",
        "()Ljava/lang/String;"
    );
    if (to_string == nullptr) {
        environment->ExceptionClear();
        environment->DeleteLocalRef(throwable_class);
        return message;
    }

    auto text = static_cast<jstring>(
        environment->CallObjectMethod(exception, to_string)
    );
    if (environment->ExceptionCheck()) {
        environment->ExceptionClear();
    } else if (text != nullptr) {
        const char *utf8 = environment->GetStringUTFChars(text, nullptr);
        if (utf8 != nullptr) {
            message = utf8;
            environment->ReleaseStringUTFChars(text, utf8);
        }
        environment->DeleteLocalRef(text);
    }

    environment->DeleteLocalRef(throwable_class);
    environment->DeleteLocalRef(exception);
    return message;
}

jstring new_utf8_string(
    JNIEnv *environment,
    const char *value,
    std::string &error
) {
    const size_t length = std::strlen(value);
    if (length > static_cast<size_t>(INT32_MAX)) {
        error = "The Java request is too large";
        return nullptr;
    }

    jbyteArray bytes = environment->NewByteArray(static_cast<jsize>(length));
    if (bytes == nullptr) {
        error = "Unable to allocate Java request bytes";
        return nullptr;
    }
    environment->SetByteArrayRegion(
        bytes,
        0,
        static_cast<jsize>(length),
        reinterpret_cast<const jbyte *>(value)
    );
    if (environment->ExceptionCheck()) {
        environment->DeleteLocalRef(bytes);
        error = java_exception_message(environment);
        return nullptr;
    }

    jclass string_class = environment->FindClass("java/lang/String");
    if (string_class == nullptr) {
        environment->DeleteLocalRef(bytes);
        error = java_exception_message(environment);
        return nullptr;
    }
    jmethodID constructor = environment->GetMethodID(
        string_class,
        "<init>",
        "([BLjava/lang/String;)V"
    );
    jstring charset = environment->NewStringUTF("UTF-8");
    if (constructor == nullptr || charset == nullptr) {
        environment->DeleteLocalRef(string_class);
        environment->DeleteLocalRef(bytes);
        if (charset != nullptr) {
            environment->DeleteLocalRef(charset);
        }
        error = environment->ExceptionCheck()
            ? java_exception_message(environment)
            : "Unable to resolve the Java UTF-8 string constructor";
        return nullptr;
    }

    auto result = static_cast<jstring>(
        environment->NewObject(string_class, constructor, bytes, charset)
    );
    environment->DeleteLocalRef(charset);
    environment->DeleteLocalRef(string_class);
    environment->DeleteLocalRef(bytes);
    if (result == nullptr || environment->ExceptionCheck()) {
        error = environment->ExceptionCheck()
            ? java_exception_message(environment)
            : "Unable to create the Java request string";
        return nullptr;
    }
    return result;
}

bool string_to_utf8(
    JNIEnv *environment,
    jstring value,
    std::string &result,
    std::string &error
) {
    jclass string_class = environment->FindClass("java/lang/String");
    if (string_class == nullptr) {
        error = java_exception_message(environment);
        return false;
    }
    jmethodID get_bytes = environment->GetMethodID(
        string_class,
        "getBytes",
        "(Ljava/lang/String;)[B"
    );
    jstring charset = environment->NewStringUTF("UTF-8");
    if (get_bytes == nullptr || charset == nullptr) {
        environment->DeleteLocalRef(string_class);
        if (charset != nullptr) {
            environment->DeleteLocalRef(charset);
        }
        error = environment->ExceptionCheck()
            ? java_exception_message(environment)
            : "Unable to resolve Java UTF-8 encoding";
        return false;
    }

    auto bytes = static_cast<jbyteArray>(
        environment->CallObjectMethod(value, get_bytes, charset)
    );
    environment->DeleteLocalRef(charset);
    environment->DeleteLocalRef(string_class);
    if (bytes == nullptr || environment->ExceptionCheck()) {
        error = environment->ExceptionCheck()
            ? java_exception_message(environment)
            : "Unable to encode the Java response";
        return false;
    }

    const jsize length = environment->GetArrayLength(bytes);
    result.resize(static_cast<size_t>(length));
    if (length > 0) {
        environment->GetByteArrayRegion(
            bytes,
            0,
            length,
            reinterpret_cast<jbyte *>(&result[0])
        );
    }
    environment->DeleteLocalRef(bytes);
    if (environment->ExceptionCheck()) {
        error = java_exception_message(environment);
        return false;
    }
    return true;
}

TJRStatus acquire_environment(
    TJRRuntime *runtime,
    JNIEnv **environment,
    bool *attached,
    char **error_message
) {
    *attached = false;
    const jint get_result = runtime->vm->GetEnv(
        reinterpret_cast<void **>(environment),
        JNI_VERSION_1_8
    );
    if (get_result == JNI_OK) {
        return TJRStatusOK;
    }
    if (get_result != JNI_EDETACHED) {
        set_error(error_message, "Unable to obtain a JNI environment");
        return TJRStatusThreadAttachFailed;
    }

    const jint attach_result = runtime->vm->AttachCurrentThread(
        reinterpret_cast<void **>(environment),
        nullptr
    );
    if (attach_result != JNI_OK) {
        set_error(error_message, "Unable to attach the current thread to Java");
        return TJRStatusThreadAttachFailed;
    }
    *attached = true;
    return TJRStatusOK;
}

} // namespace

TJRRuntime *tjr_runtime_create(
    const char *java_home,
    const char *frameworks_directory,
    const char *classpath,
    const char *const *additional_options,
    int additional_option_count,
    char **error_message
) {
    if (error_message != nullptr) {
        *error_message = nullptr;
    }
    if (
        java_home == nullptr ||
        frameworks_directory == nullptr ||
        classpath == nullptr ||
        additional_option_count < 0
    ) {
        set_error(error_message, "Invalid JVM runtime configuration");
        return nullptr;
    }

#if !defined(__APPLE__)
    (void)additional_options;
    set_error(
        error_message,
        "The embedded JVM bridge currently supports Apple platforms only"
    );
    return nullptr;
#else
    auto *runtime = new (std::nothrow) TJRRuntime();
    if (runtime == nullptr) {
        set_error(error_message, "Unable to allocate JVM runtime");
        return nullptr;
    }
    runtime->vm = nullptr;

    setenv("JAVA_HOME", java_home, 1);

    const char *required_libraries[] = {
        "libffi.8",
        "libjvm",
        "libverify",
        "libjava",
        "libnet",
    };
    void *jvm_handle = nullptr;
    for (const char *library : required_libraries) {
        std::string loader_error;
        void *handle = load_framework(
            frameworks_directory,
            library,
            loader_error
        );
        if (handle == nullptr) {
            set_error(error_message, loader_error);
            for (void *loaded_handle : runtime->library_handles) {
                dlclose(loaded_handle);
            }
            delete runtime;
            return nullptr;
        }
        runtime->library_handles.push_back(handle);
        if (std::strcmp(library, "libjvm") == 0) {
            jvm_handle = handle;
        }
    }

    using CreateJavaVM = jint (*)(JavaVM **, void **, void *);
    auto create_vm = reinterpret_cast<CreateJavaVM>(
        dlsym(jvm_handle, "JNI_CreateJavaVM")
    );
    if (create_vm == nullptr) {
        set_error(error_message, "libjvm does not export JNI_CreateJavaVM");
        for (void *loaded_handle : runtime->library_handles) {
            dlclose(loaded_handle);
        }
        delete runtime;
        return nullptr;
    }

    std::vector<std::string> option_values = {
        std::string("-Djava.home=") + java_home,
        std::string("-Djava.class.path=") + classpath,
        std::string("-Djava.library.path=") + frameworks_directory,
        "-Djava.awt.headless=true",
        "-XX:+UnlockExperimentalVMOptions",
        "-XX:+DisablePrimordialThreadGuardPages",
        "-XX:-UseCompressedClassPointers",
        "-Xrs",
        "-Xmx192m",
    };
    for (int index = 0; index < additional_option_count; ++index) {
        if (
            additional_options != nullptr &&
            additional_options[index] != nullptr
        ) {
            option_values.emplace_back(additional_options[index]);
        }
    }

    std::vector<JavaVMOption> options(option_values.size());
    for (size_t index = 0; index < option_values.size(); ++index) {
        options[index].optionString =
            const_cast<char *>(option_values[index].c_str());
        options[index].extraInfo = nullptr;
    }

    JavaVMInitArgs arguments;
    arguments.version = JNI_VERSION_1_8;
    arguments.nOptions = static_cast<jint>(options.size());
    arguments.options = options.data();
    arguments.ignoreUnrecognized = JNI_FALSE;

    JNIEnv *environment = nullptr;
    const jint result = create_vm(
        &runtime->vm,
        reinterpret_cast<void **>(&environment),
        &arguments
    );
    if (
        result != JNI_OK ||
        runtime->vm == nullptr ||
        environment == nullptr
    ) {
        set_error(
            error_message,
            "JNI_CreateJavaVM failed with code " + std::to_string(result)
        );
        for (void *loaded_handle : runtime->library_handles) {
            dlclose(loaded_handle);
        }
        delete runtime;
        return nullptr;
    }

    return runtime;
#endif
}

TJRStatus tjr_runtime_dispatch(
    TJRRuntime *runtime,
    const char *request_json,
    char **response_json,
    char **error_message
) {
    if (response_json != nullptr) {
        *response_json = nullptr;
    }
    if (error_message != nullptr) {
        *error_message = nullptr;
    }
    if (
        runtime == nullptr ||
        runtime->vm == nullptr ||
        request_json == nullptr
    ) {
        set_error(error_message, "Invalid dispatch arguments");
        return TJRStatusInvalidArgument;
    }

    JNIEnv *environment = nullptr;
    bool attached = false;
    const TJRStatus acquire_status = acquire_environment(
        runtime,
        &environment,
        &attached,
        error_message
    );
    if (acquire_status != TJRStatusOK) {
        return acquire_status;
    }

    TJRStatus status = TJRStatusOK;
    jclass host_class = environment->FindClass(
        "app/tachiaz/runtime/ExtensionHost"
    );
    if (host_class == nullptr) {
        set_error(error_message, java_exception_message(environment));
        status = TJRStatusJavaClassNotFound;
        goto cleanup;
    }

    {
        jmethodID dispatch_method = environment->GetStaticMethodID(
            host_class,
            "dispatch",
            "(Ljava/lang/String;)Ljava/lang/String;"
        );
        if (dispatch_method == nullptr) {
            set_error(error_message, java_exception_message(environment));
            status = TJRStatusJavaMethodNotFound;
            goto cleanup;
        }

        std::string conversion_error;
        jstring request = new_utf8_string(
            environment,
            request_json,
            conversion_error
        );
        if (request == nullptr) {
            set_error(error_message, conversion_error);
            status = TJRStatusAllocationFailed;
            goto cleanup;
        }

        auto response = static_cast<jstring>(
            environment->CallStaticObjectMethod(
                host_class,
                dispatch_method,
                request
            )
        );
        environment->DeleteLocalRef(request);
        if (environment->ExceptionCheck()) {
            set_error(error_message, java_exception_message(environment));
            status = TJRStatusJavaException;
            goto cleanup;
        }
        if (response == nullptr) {
            set_error(error_message, "ExtensionHost returned a null response");
            status = TJRStatusJavaException;
            goto cleanup;
        }

        std::string utf8;
        std::string response_error;
        const bool converted = string_to_utf8(
            environment,
            response,
            utf8,
            response_error
        );
        environment->DeleteLocalRef(response);
        if (!converted) {
            set_error(error_message, response_error);
            status = TJRStatusAllocationFailed;
            goto cleanup;
        }
        if (response_json != nullptr) {
            *response_json = copy_string(utf8);
        }
        if (
            response_json != nullptr &&
            *response_json == nullptr
        ) {
            set_error(error_message, "Unable to allocate the native response");
            status = TJRStatusAllocationFailed;
        }
    }

cleanup:
    if (host_class != nullptr) {
        environment->DeleteLocalRef(host_class);
    }
    if (attached) {
        runtime->vm->DetachCurrentThread();
    }
    return status;
}

void tjr_runtime_release(TJRRuntime *runtime) {
    if (runtime == nullptr) {
        return;
    }
    // Deliberately keep the JVM and its frameworks loaded until process exit.
    delete runtime;
}

void tjr_string_free(char *value) {
    std::free(value);
}
