package app.tachiaz.runtime;

import java.io.BufferedInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.util.jar.JarEntry;
import java.util.jar.JarInputStream;

final class JarBytecodeValidator {
    private static final int JAVA_8_CLASS_VERSION = 52;

    private JarBytecodeValidator() {
    }

    static void validate(File jar) throws IOException {
        if (!jar.isFile()) {
            throw new IllegalArgumentException(
                "Extension JAR does not exist: " + jar
            );
        }

        boolean foundClass = false;
        try (
            JarInputStream input = new JarInputStream(
                new BufferedInputStream(new FileInputStream(jar))
            )
        ) {
            JarEntry entry;
            byte[] header = new byte[8];
            while ((entry = input.getNextJarEntry()) != null) {
                if (
                    entry.isDirectory() ||
                    !entry.getName().endsWith(".class")
                ) {
                    continue;
                }
                foundClass = true;
                readFully(input, header);
                if (
                    (header[0] & 0xff) != 0xca ||
                    (header[1] & 0xff) != 0xfe ||
                    (header[2] & 0xff) != 0xba ||
                    (header[3] & 0xff) != 0xbe
                ) {
                    throw new IllegalArgumentException(
                        "Invalid class header in " + entry.getName()
                    );
                }
                int major = ((header[6] & 0xff) << 8) | (header[7] & 0xff);
                if (major > JAVA_8_CLASS_VERSION) {
                    throw new IllegalArgumentException(
                        entry.getName() + " uses class-file version " + major +
                            "; this runtime supports at most " +
                            JAVA_8_CLASS_VERSION
                    );
                }
            }
        }

        if (!foundClass) {
            throw new IllegalArgumentException(
                "Extension JAR contains no classes"
            );
        }
    }

    private static void readFully(JarInputStream input, byte[] buffer)
        throws IOException {
        int offset = 0;
        while (offset < buffer.length) {
            int count = input.read(buffer, offset, buffer.length - offset);
            if (count < 0) {
                throw new IOException("Truncated class file");
            }
            offset += count;
        }
    }
}
