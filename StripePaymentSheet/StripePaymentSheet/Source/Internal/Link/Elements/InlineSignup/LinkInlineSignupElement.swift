//
//  LinkInlineSignupElement.swift
//  StripePaymentSheet
//
//  Created by Ramon Torres on 1/20/22.
//  Copyright © 2022 Stripe, Inc. All rights reserved.
//

@_spi(STP) import StripeUICore
import UIKit

final class LinkInlineSignupElement: Element {

    private let signupView: LinkInlineSignupView

    lazy var view: UIView = {

        return FormView(viewModel: .init(elements: [signupView],
                                         bordered: viewModel.bordered,
                                         theme: viewModel.configuration.appearance.asElementsTheme))
    }()

    var viewModel: LinkInlineSignupViewModel {
        return signupView.viewModel
    }

    weak var delegate: ElementDelegate?

    var isChecked: Bool {
        return viewModel.saveCheckboxChecked
    }

    var action: LinkInlineSignupViewModel.Action? {
        return viewModel.action
    }

    convenience init(
        configuration: PaymentSheet.Configuration,
        linkAccount: PaymentSheetLinkAccount?,
        country: String?,
        mode: LinkInlineSignupViewModel.Mode
    ) {
        self.init(viewModel: LinkInlineSignupViewModel(
            configuration: configuration,
            mode: mode,
            accountService: LinkAccountService(apiClient: configuration.apiClient),
            linkAccount: linkAccount,
            country: country
        ))
    }

    init(viewModel: LinkInlineSignupViewModel) {
        self.signupView = LinkInlineSignupView(viewModel: viewModel)
        self.signupView.delegate = self
    }

}

extension LinkInlineSignupElement: LinkInlineSignupViewDelegate {

    func inlineSignupViewDidUpdate(_ view: LinkInlineSignupView) {
        delegate?.didUpdate(element: self)
    }

}
