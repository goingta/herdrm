import HerdrKit

extension Device {
    var localizedSubtitle: String {
        switch kind {
        case .local:
            return AppLocalization.string("This Mac · herdr.sock")
        case .ssh(let target):
            return AppLocalization.string("\(target) · SSH")
        case .tailcat:
            return AppLocalization.string("tailcat tunnel")
        }
    }
}
