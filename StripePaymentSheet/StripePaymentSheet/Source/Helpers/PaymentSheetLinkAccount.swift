//
//  PaymentSheetLinkAccount.swift
//  StripePaymentSheet
//
//  Created by Cameron Sabol on 7/8/21.
//  Copyright © 2021 Stripe, Inc. All rights reserved.
//

@_spi(STP) import StripeCore
@_spi(STP) import StripePayments
@_spi(STP) import StripeUICore
import UIKit

protocol PaymentSheetLinkAccountInfoProtocol {
    var email: String { get }
    var lastPM: LinkPMDisplayDetails? { get }
    var redactedPhoneNumber: String? { get }
    var isRegistered: Bool { get }
    var isLoggedIn: Bool { get }
}

struct LinkPMDisplayDetails {
    let last4: String
    let brand: STPCardBrand
}

class PaymentSheetLinkAccount: PaymentSheetLinkAccountInfoProtocol {
    enum SessionState: String {
        case requiresSignUp
        case requiresVerification
        case verified
    }

    enum ConsentAction: String {
        case checkbox = "clicked_checkbox_mobile"
        case button = "clicked_button_mobile"
    }

    // Dependencies
    let apiClient: STPAPIClient
    let cookieStore: LinkCookieStore

    /// Publishable key of the Consumer Account.
    private(set) var publishableKey: String?

    let email: String
    var last4: String?
    var lastBrand: STPCardBrand?

    var lastPM: LinkPMDisplayDetails? {
        let linkAccountService = LinkAccountService(cookieStore: cookieStore)
        return linkAccountService.getLastPMDetails()
    }

    var redactedPhoneNumber: String? {
        return currentSession?.redactedPhoneNumber
    }

    var isRegistered: Bool {
        return currentSession != nil
    }

    var isLoggedIn: Bool {
        return sessionState == .verified
    }

    var sessionState: SessionState {
        if let currentSession = currentSession {
            // sms verification is not required if we are in the signup flow
            return currentSession.hasVerifiedSMSSession || currentSession.isVerifiedForSignup
                ? .verified : .requiresVerification
        } else {
            return .requiresSignUp
        }
    }

    var hasStartedSMSVerification: Bool {
        return currentSession?.hasStartedSMSVerification ?? false
    }

    private var currentSession: ConsumerSession?

    init(
        email: String,
        session: ConsumerSession?,
        publishableKey: String?,
        apiClient: STPAPIClient = .shared,
        cookieStore: LinkCookieStore = LinkSecureCookieStore.shared
    ) {
        self.email = email
        self.currentSession = session
        self.publishableKey = publishableKey
        self.apiClient = apiClient
        self.cookieStore = cookieStore
    }

    func signUp(
        with phoneNumber: PhoneNumber,
        legalName: String?,
        consentAction: ConsentAction,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        signUp(
            with: phoneNumber.string(as: .e164),
            legalName: legalName,
            countryCode: phoneNumber.countryCode,
            consentAction: consentAction,
            completion: completion
        )
    }

    func signUp(
        with phoneNumber: String,
        legalName: String?,
        countryCode: String?,
        consentAction: ConsentAction,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard case .requiresSignUp = sessionState else {
            STPAnalyticsClient.sharedClient.logLinkInvalidSessionState(sessionState: sessionState)
            DispatchQueue.main.async {
                completion(
                    .failure(
                        PaymentSheetError.linkSignUpNotRequired
                    )
                )
            }
            return
        }

        ConsumerSession.signUp(
            email: email,
            phoneNumber: phoneNumber,
            legalName: legalName,
            countryCode: countryCode,
            consentAction: consentAction.rawValue,
            with: apiClient,
            cookieStore: cookieStore
        ) { [weak self] result in
            switch result {
            case .success(let signupResponse):
                self?.currentSession = signupResponse.consumerSession
                self?.publishableKey = signupResponse.publishableKey
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func createLinkAccountSession(
        completion: @escaping (Result<LinkAccountSession, Error>) -> Void
    ) {
        guard let session = currentSession else {
            assertionFailure()
            completion(
                .failure(
                    PaymentSheetError.linkingWithoutValidSession
                )
            )
            return
        }

        retryingOnAuthError(completion: completion) { [publishableKey] completionWrapper in
            session.createLinkAccountSession(
                consumerAccountPublishableKey: publishableKey,
                completion: completionWrapper
            )
        }
    }

    func createPaymentDetails(
        with paymentMethodParams: STPPaymentMethodParams,
        completion: @escaping (Result<ConsumerPaymentDetails, Error>) -> Void
    ) {
        guard let session = currentSession else {
            assertionFailure()
            completion(
                .failure(PaymentSheetError.savingWithoutValidLinkSession)
            )
            return
        }

        retryingOnAuthError(completion: completion) { [apiClient, publishableKey] completionWrapper in
            session.createPaymentDetails(
                paymentMethodParams: paymentMethodParams,
                with: apiClient,
                consumerAccountPublishableKey: publishableKey,
                completion: completionWrapper
            )
        }
    }

    func createPaymentDetails(
        linkedAccountId: String,
        completion: @escaping (Result<ConsumerPaymentDetails, Error>) -> Void
    ) {
        guard let session = currentSession else {
            assertionFailure()
            completion(.failure(PaymentSheetError.savingWithoutValidLinkSession))
            return
        }
        retryingOnAuthError(completion: completion) { [publishableKey] completionWrapper in
            session.createPaymentDetails(
                linkedAccountId: linkedAccountId,
                consumerAccountPublishableKey: publishableKey,
                completion: completionWrapper
            )
        }
    }

    func listPaymentDetails(
        completion: @escaping (Result<[ConsumerPaymentDetails], Error>) -> Void
    ) {
        guard let session = currentSession else {
            assertionFailure()
            completion(.failure(PaymentSheetError.payingWithoutValidLinkSession))
            return
        }

        retryingOnAuthError(completion: completion) { [apiClient, publishableKey] completionWrapper in
            session.listPaymentDetails(
                with: apiClient,
                consumerAccountPublishableKey: publishableKey,
                completion: completionWrapper
            )
        }
    }

    func sharePaymentDetails(id: String, completion: @escaping (Result<PaymentDetailsShareResponse, Error>) -> Void) {
        guard let session = currentSession else {
            assertionFailure()
            return completion(
                .failure(
                    PaymentSheetError.savingWithoutValidLinkSession
                )
            )
        }

        retryingOnAuthError(completion: completion) { [apiClient, publishableKey] completionWrapper in
            session.sharePaymentDetails(
                with: apiClient,
                id: id,
                consumerAccountPublishableKey: publishableKey,
                completion: completionWrapper
            )
        }
    }

    func deletePaymentDetails(id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let session = currentSession else {
            assertionFailure()
            return completion(
                .failure(
                    PaymentSheetError.deletingWithoutValidLinkSession
                )
            )
        }

        retryingOnAuthError(completion: completion) { [apiClient, publishableKey] completionWrapper in
            session.deletePaymentDetails(
                with: apiClient,
                id: id,
                consumerAccountPublishableKey: publishableKey,
                completion: completionWrapper
            )
        }
    }

    func updatePaymentDetails(
        id: String,
        updateParams: UpdatePaymentDetailsParams,
        completion: @escaping (Result<ConsumerPaymentDetails, Error>) -> Void
    ) {
        guard let session = currentSession else {
            assertionFailure()
            return completion(
                .failure(
                    PaymentSheetError.updatingWithoutValidLinkSession
                )
            )
        }

        retryingOnAuthError(completion: completion) { [apiClient, publishableKey] completionWrapper in
            session.updatePaymentDetails(
                with: apiClient,
                id: id,
                updateParams: updateParams,
                consumerAccountPublishableKey: publishableKey,
                completion: completionWrapper
            )
        }
    }

    func logout(completion: (() -> Void)? = nil) {
        guard let session = currentSession else {
            assertionFailure("Cannot logout without an active session")
            completion?()
            return
        }

        session.logout(
            with: apiClient,
            cookieStore: cookieStore,
            consumerAccountPublishableKey: publishableKey
        ) { _ in
            completion?()
        }

        // Delete cookie.
        cookieStore.delete(key: .session)

        markEmailAsLoggedOut()

        // Forget current session.
        self.currentSession = nil
    }

    func markEmailAsLoggedOut() {
        guard let hashedEmail = email.lowercased().sha256 else {
            return
        }

        cookieStore.write(key: .lastLogoutEmail, value: hashedEmail)
    }

}

// MARK: - Equatable

extension PaymentSheetLinkAccount: Equatable {

    static func == (lhs: PaymentSheetLinkAccount, rhs: PaymentSheetLinkAccount) -> Bool {
        return
            (lhs.email == rhs.email && lhs.currentSession == rhs.currentSession
            && lhs.publishableKey == rhs.publishableKey)
    }

}

// MARK: - Session refresh

private extension PaymentSheetLinkAccount {

    typealias CompletionBlock<T> = (Result<T, Error>) -> Void

    func retryingOnAuthError<T>(
        completion: @escaping CompletionBlock<T>,
        apiCall: @escaping (@escaping CompletionBlock<T>) -> Void
    ) {
        apiCall { [weak self] result in
            switch result {
            case .success:
                completion(result)
            case .failure(let error as NSError):
                let isAuthError =
                    (error.domain == STPError.stripeDomain && error.code == STPErrorCode.authenticationError.rawValue)

                if isAuthError {
                    self?.refreshSession { refreshSessionResult in
                        switch refreshSessionResult {
                        case .success:
                            apiCall(completion)
                        case .failure:
                            completion(result)
                        }
                    }
                } else {
                    completion(result)
                }
            }
        }
    }

    func refreshSession(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // The consumer session lookup endpoint currently serves as our endpoint for
        // refreshing the session. To refresh the session, we need to call this endpoint
        // without providing an email address.
        ConsumerSession.lookupSession(
            for: nil,  // No email address
            with: apiClient,
            cookieStore: cookieStore
        ) { [weak self] result in
            switch result {
            case .success(let response):
                switch response.responseType {
                case .found(let session):
                    self?.currentSession = session.consumerSession
                    self?.publishableKey = session.publishableKey
                    completion(.success(()))
                case .notFound(let message):
                    completion(
                        .failure(PaymentSheetError.linkLookupNotFound(serverErrorMessage: message))
                    )
                case .noAvailableLookupParams:
                    completion(
                        .failure(PaymentSheetError.missingClientSecret)
                    )
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

}

// MARK: - Payment method params

extension PaymentSheetLinkAccount {

    /// Converts a `ConsumerPaymentDetails` into a `STPPaymentMethodParams` object, injecting
    /// the required Link credentials.
    ///
    /// Returns `nil` if not authenticated/logged in.
    ///
    /// - Parameter paymentDetails: Payment details
    /// - Returns: Payment method params for paying with Link.
    func makePaymentMethodParams(from paymentDetails: ConsumerPaymentDetails) -> STPPaymentMethodParams? {
        guard let currentSession = currentSession else {
            assertionFailure("Cannot make payment method params without an active session.")
            return nil
        }

        let params = STPPaymentMethodParams(type: .link)
        params.link?.paymentDetailsID = paymentDetails.stripeID
        params.link?.credentials = ["consumer_session_client_secret": currentSession.clientSecret]

        if let cvc = paymentDetails.cvc {
            params.link?.additionalAPIParameters["card"] = [
                "cvc": cvc,
            ]
        }

        return params
    }

}

// MARK: - Payment method availability

extension PaymentSheetLinkAccount {

    /// Returns a set containing the Payment Details types that the user is able to use for confirming the given `intent`.
    /// - Parameter intent: The Intent that the user is trying to confirm.
    /// - Returns: A set containing the supported Payment Details types.
    func supportedPaymentDetailsTypes(for intent: Intent) -> Set<ConsumerPaymentDetails.DetailsType> {
        guard let currentSession = currentSession, let fundingSources = intent.linkFundingSources else {
            return []
        }

        let fundingSourceDetailsTypes = Set(fundingSources.compactMap { $0.detailsType })

        // Take the intersection of the consumer session types and the merchant-provided Link funding sources
        var supportedPaymentDetailsTypes = fundingSourceDetailsTypes.intersection(currentSession.supportedPaymentDetailsTypes)

        // Special testmode handling
        if apiClient.isTestmode && Self.emailSupportsMultipleFundingSourcesOnTestMode(email) {
            supportedPaymentDetailsTypes.insert(.bankAccount)
        }

        return supportedPaymentDetailsTypes
    }

    func supportedPaymentMethodTypes(for intent: Intent) -> [STPPaymentMethodType] {
        var supportedPaymentMethodTypes = [STPPaymentMethodType]()

        for paymentDetailsType in supportedPaymentDetailsTypes(for: intent) {
            switch paymentDetailsType {
            case .card:
                supportedPaymentMethodTypes.append(.card)
            case .bankAccount:
                supportedPaymentMethodTypes.append(.linkInstantDebit)
            case .unparsable:
                break
            }
        }

        if supportedPaymentMethodTypes.isEmpty {
            // Card is the default payment method type when no other type is available.
            supportedPaymentMethodTypes.append(.card)
        }

        return supportedPaymentMethodTypes
    }
}

// MARK: - Helpers

private extension PaymentSheetLinkAccount {

    /// On *testmode* we use special email addresses for testing multiple funding sources. This method returns `true`
    /// if the given `email` is one of such email addresses.
    ///
    /// - Parameter email: Email.
    /// - Returns: Whether or not should enable multiple funding sources on test mode.
    static func emailSupportsMultipleFundingSourcesOnTestMode(_ email: String) -> Bool {
        return email.contains("+multiple_funding_sources@")
    }

}

private extension LinkSettings.FundingSource {
    var detailsType: ConsumerPaymentDetails.DetailsType? {
        switch self {
        case .card:
            return .card
        case .bankAccount:
            return .bankAccount
        }
    }
}

// MARK: UpdatePaymentDetailsParams

struct UpdatePaymentDetailsParams {
    enum DetailsType {
        case card(expiryDate: CardExpiryDate, billingDetails: STPPaymentMethodBillingDetails? = nil)
        // updating bank not supported
    }

    let isDefault: Bool?
    let details: DetailsType?

    init(isDefault: Bool? = nil, details: DetailsType? = nil) {
        self.isDefault = isDefault
        self.details = details
    }
}
