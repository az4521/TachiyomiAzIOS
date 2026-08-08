//
//  LibraryCategorySelectionHeader.swift
//  Aidoku
//
//  Created by Skitty on 2/25/26.
//

import UIKit

protocol LibraryCategorySelectionHeaderDelegate: AnyObject {
    func optionSelected(_ indexPath: IndexPath)
}

/// A Material-style, horizontally scrolling tab strip for library categories.
class LibraryCategorySelectionHeader: UICollectionReusableView {
    weak var delegate: LibraryCategorySelectionHeaderDelegate?

    struct Section {
        var title: String?
        var options: [String] = []
    }

    var options: [Section] = [] {
        didSet {
            if !contains(selectedIndexPath) {
                selectedIndexPath = IndexPath(row: 0, section: 0)
            }
            rebuildTabs()
        }
    }

    var lockedOptions: [IndexPath] = [] {
        didSet { rebuildTabs() }
    }

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let selectionIndicator = UIView()
    private let bottomDivider = UIView()

    private var tabButtons: [UIButton] = []
    private var tabIndexPaths: [IndexPath] = []
    private var selectedIndexPath = IndexPath(row: 0, section: 0)
    private var animateNextIndicatorUpdate = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateSelectionIndicator(animated: animateNextIndicatorUpdate)
        animateNextIndicatorUpdate = false
    }

    private func configure() {
        backgroundColor = .systemBackground

        scrollView.alwaysBounceHorizontal = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(scrollView)

        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = 0
        scrollView.addSubview(stackView)

        selectionIndicator.backgroundColor = tintColor
        selectionIndicator.layer.cornerRadius = 1.5
        scrollView.addSubview(selectionIndicator)

        bottomDivider.backgroundColor = .separator
        addSubview(bottomDivider)
    }

    private func constrain() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        bottomDivider.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 4),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -4),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

            bottomDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomDivider.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomDivider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        selectionIndicator.backgroundColor = tintColor
        updateButtonAppearance()
    }

    private func contains(_ indexPath: IndexPath) -> Bool {
        options.indices.contains(indexPath.section)
            && options[indexPath.section].options.indices.contains(indexPath.row)
    }

    private func rebuildTabs() {
        tabButtons.forEach { $0.removeFromSuperview() }
        tabButtons.removeAll(keepingCapacity: true)
        tabIndexPaths.removeAll(keepingCapacity: true)

        for (sectionIndex, section) in options.enumerated() {
            for (rowIndex, title) in section.options.enumerated() {
                let indexPath = IndexPath(row: rowIndex, section: sectionIndex)
                let button = UIButton(type: .system)
                var configuration = UIButton.Configuration.plain()
                configuration.title = title
                configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
                configuration.imagePadding = 5
                if lockedOptions.contains(indexPath) {
                    configuration.image = UIImage(systemName: "lock.fill")
                    configuration.imagePlacement = .leading
                }
                button.configuration = configuration
                button.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
                button.titleLabel?.adjustsFontForContentSizeCategory = true
                button.accessibilityIdentifier = "library-category-tab-\(sectionIndex)-\(rowIndex)"
                button.addTarget(self, action: #selector(tabPressed(_:)), for: .touchUpInside)
                stackView.addArrangedSubview(button)
                tabButtons.append(button)
                tabIndexPaths.append(indexPath)
            }
        }

        updateButtonAppearance()
        setNeedsLayout()
    }

    private func updateButtonAppearance() {
        for (button, indexPath) in zip(tabButtons, tabIndexPaths) {
            let selected = indexPath == selectedIndexPath
            button.configuration?.baseForegroundColor = selected ? tintColor : .secondaryLabel
            button.titleLabel?.font = selected
                ? .preferredFont(forTextStyle: .headline)
                : .preferredFont(forTextStyle: .subheadline)
            button.accessibilityTraits = selected ? [.button, .selected] : .button
        }
    }

    private func updateSelectionIndicator(animated: Bool) {
        guard
            let selectedIndex = tabIndexPaths.firstIndex(of: selectedIndexPath),
            tabButtons.indices.contains(selectedIndex)
        else {
            selectionIndicator.isHidden = true
            return
        }

        selectionIndicator.isHidden = false
        let button = tabButtons[selectedIndex]
        let buttonFrame = button.convert(button.bounds, to: scrollView)
        let minimumWidth: CGFloat = 24
        let horizontalInset: CGFloat = 14
        let targetWidth = max(minimumWidth, buttonFrame.width - horizontalInset * 2)
        let targetFrame = CGRect(
            x: buttonFrame.midX - targetWidth / 2,
            y: bounds.height - 3,
            width: targetWidth,
            height: 3
        )
        let changes = { self.selectionIndicator.frame = targetFrame }
        if animated, !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .curveEaseOut], animations: changes)
        } else {
            changes()
        }
        scrollView.scrollRectToVisible(buttonFrame.insetBy(dx: -12, dy: 0), animated: animated)
    }

    @objc private func tabPressed(_ sender: UIButton) {
        guard
            let index = tabButtons.firstIndex(of: sender),
            tabIndexPaths.indices.contains(index)
        else { return }
        setSelectedOption(tabIndexPaths[index], notifyDelegate: true, animated: true)
    }

    func setSelectedOption(_ indexPath: IndexPath, notifyDelegate: Bool = false, animated: Bool = false) {
        guard contains(indexPath) else { return }
        let changed = selectedIndexPath != indexPath
        selectedIndexPath = indexPath
        updateButtonAppearance()
        animateNextIndicatorUpdate = animated
        setNeedsLayout()
        layoutIfNeeded()
        if notifyDelegate, changed {
            delegate?.optionSelected(indexPath)
        }
    }
}
