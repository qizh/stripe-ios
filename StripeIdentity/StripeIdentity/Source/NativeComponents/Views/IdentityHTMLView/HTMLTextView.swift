//
//  HTMLTextView.swift
//  StripeIdentity
//
//  Created by Mel Ludowise on 2/25/22.
//  Copyright © 2022 Stripe, Inc. All rights reserved.
//

import Foundation
@_spi(STP) import StripeUICore
import UIKit

final class HTMLTextView: UIView {
    struct ViewModel {
        enum Style {
            /// Text should render as HTML
            /// - `makeStyle`: Computes the style to apply for the current size category
            case html(makeStyle: () -> HTMLStyle)
            /// Text should render as plain text
            /// - `font`: The font to apply to the text
            /// - `textColor`: The color to apply to the text
            case plainText(font: UIFont, textColor: UIColor)
        }

        let text: String
        let style: Style
        let didOpenURL: (URL) -> Void
    }

    private lazy var textView: UITextView = {
        let textView: UITextView

        // iOS 13 requires that the TextView be editable for links to open but
        // iOS 14 does not.
        if #available(iOS 14, *) {
            textView = UITextView()
            textView.isEditable = false
        } else {
            // Remove the spelling rotor so the voice over doesn't say,
            // "use the rotor to access misspelled words"
            textView = TextViewWithoutSpellingRotor()
            // Tell the voice over engine that this is static text so it doesn't
            // say, "double tap to edit"
            textView.accessibilityTraits = .staticText
        }

        textView.isScrollEnabled = false
        textView.backgroundColor = nil
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.delegate = self
        return textView
    }()

    private var viewModel: ViewModel?

    init() {
        super.init(frame: .zero)
        self.addAndPinSubview(textView)
    }

    required init?(
        coder: NSCoder
    ) {
        fatalError("init(coder:) has not been implemented")
    }

    // Check if htmlText is <ul></ul>, if so, return the <li> within, return nil otherwise
    fileprivate func tryParseUl(htmlString: String) -> [String]? {
        let trimmedHtmlString = htmlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmedHtmlString.startIndex..<trimmedHtmlString.endIndex, in: trimmedHtmlString)
        let regex = try? NSRegularExpression(pattern: "^<ul>.*</ul>$", options: .dotMatchesLineSeparators)
        if regex?.firstMatch(in: trimmedHtmlString, options: [], range: range) == nil {
            return nil
        }

        // Extract list items
        var items: [String] = []
        let itemRegex = try? NSRegularExpression(pattern: "<li>(.*?)</li>", options: .dotMatchesLineSeparators)
        let matches = itemRegex?.matches(in: trimmedHtmlString, options: [], range: range) ?? []

        for match in matches {
            if let range = Range(match.range(at: 1), in: trimmedHtmlString) {
                items.append(String(trimmedHtmlString[range]))
            }
        }
        return items
    }

    func configure(with viewModel: ViewModel) throws {

        switch viewModel.style {
        case .html(let makeStyle):
            let htmlStyle = makeStyle()
            // NSAttributedString cannot properly render CSS with <ul> and <li>, build a plain string instead
            if let parsedListItems = tryParseUl(htmlString: viewModel.text) {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineHeightMultiple = htmlStyle.lineHeightMultiple
                let attributes: [NSAttributedString.Key: Any] = [
                    .paragraphStyle: paragraphStyle
                ]
                textView.attributedText = NSAttributedString(string: parsedListItems.map { "• " + $0 }.joined(separator: "\n"), attributes: attributes)
                textView.textColor = htmlStyle.bodyColor
                textView.font = htmlStyle.bodyFont
            } else {
                textView.attributedText = try NSAttributedString.createHtmlString(
                    htmlText: viewModel.text,
                    style: htmlStyle
                )
                if let linkColor = htmlStyle.linkColor {
                    textView.linkTextAttributes = [
                        .foregroundColor: linkColor
                    ]
                }
            }
        case .plainText(let font, let textColor):
            textView.text = viewModel.text
            textView.font = font
            textView.textColor = textColor
        }

        // Cache the viewModel only if an error was not thrown creating an
        // attributed string
        self.viewModel = viewModel
    }

    // MARK: UIView

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard let viewModel = viewModel, case .html = viewModel.style
        else {
            return
        }

        // NOTE: `traitCollectionDidChange` is called off the main thread when the app backgrounds
        DispatchQueue.main.async { [weak self] in
            do {
                // Reconfigure to compute attributed text with updated font sizes
                try self?.configure(with: viewModel)
            } catch {
                // Ignore errors thrown. This means the font size won't update,
                // but the text should still display if an error wasn't already
                // thrown from `configure`.
            }
        }
    }

}

extension HTMLTextView: UITextViewDelegate {
	#if !os(visionOS)
    func textView(
        _ textView: UITextView,
        shouldInteractWith url: URL,
        in characterRange: NSRange
    ) -> Bool {
        viewModel?.didOpenURL(url)
        return false
    }
	#endif /// visionOS

    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        // textView.isEditable must be true for links to be able to be opened on
        // iOS 13, so always return false to disable edit-ability
        return false
    }
}

/// A UITextView without the misspelled words rotor
private class TextViewWithoutSpellingRotor: UITextView {
    override var accessibilityCustomRotors: [UIAccessibilityCustomRotor]? {
        get {
            // Removes the misspelled word rotor from the accessibility rotors
            return super.accessibilityCustomRotors?.filter { $0.systemRotorType != .misspelledWord }
        }
        set {
            super.accessibilityCustomRotors = newValue
        }
    }
}
