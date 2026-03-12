import Foundation

enum SuperuserAccessCategory: String, CaseIterable {
    case development
    case debugging
    case validateFeature = "validate_feature"
    case adminActions = "_admin_actions"
    case organizationSettingChange = "organization_setting_change"
    case zendesk
    case accountReview = "account_review"
    case customerDemo = "customer_demo"
    case customerProvisioning = "customer_provisioning"
    case onboardingSetup = "onboarding_setup"
    case other

    var displayName: String {
        switch self {
        case .development: return "Development"
        case .debugging: return "Debugging"
        case .validateFeature: return "Validate Feature"
        case .adminActions: return "Admin Actions"
        case .organizationSettingChange: return "Organization Setting Change"
        case .zendesk: return "Zendesk"
        case .accountReview: return "Account Review"
        case .customerDemo: return "Customer Demo"
        case .customerProvisioning: return "Customer Provisioning"
        case .onboardingSetup: return "Onboarding Setup"
        case .other: return "Other"
        }
    }

    var groupName: String {
        switch self {
        case .development, .debugging, .validateFeature:
            return "Engineering"
        case .adminActions, .organizationSettingChange, .zendesk:
            return "Reactive Support"
        case .customerDemo, .customerProvisioning, .onboardingSetup:
            return "Proactive Support"
        case .accountReview, .other:
            return "Other"
        }
    }
}

struct SuperuserAccessCategoryGroup {
    let name: String
    let categories: [SuperuserAccessCategory]

    static let all: [SuperuserAccessCategoryGroup] = [
        SuperuserAccessCategoryGroup(
            name: "Engineering",
            categories: [.development, .debugging, .validateFeature]
        ),
        SuperuserAccessCategoryGroup(
            name: "Reactive Support",
            categories: [.adminActions, .organizationSettingChange, .zendesk]
        ),
        SuperuserAccessCategoryGroup(
            name: "Proactive Support",
            categories: [.customerDemo, .customerProvisioning, .onboardingSetup]
        ),
        SuperuserAccessCategoryGroup(
            name: "Other",
            categories: [.accountReview, .other]
        ),
    ]
}

struct WebAuthnResponse {
    let keyHandle: String
    let clientData: String
    let signatureData: String
    let authenticatorData: String
}

enum PendingSuperuserRetry {
    case url(String)
    case curl(String)
}
