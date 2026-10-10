import AppKit
import HerdrKit
import SwiftUI

/// Agent-kind icon + label, used in sidebar rows and the detail header.
struct AgentKindBadge: View {
    let kind: String
    var iconSize: CGFloat = 11
    var fontSize: CGFloat = 11.5
    var color: Color = Theme.textTertiary

    var body: some View {
        HStack(spacing: 4) {
            if let resource = BrandIconLoader.agentIcon(for: kind) {
                BrandIcon(resource: resource, size: iconSize)
                    .foregroundStyle(color)
            }
            Text(kind)
                .font(.system(size: fontSize))
                .foregroundStyle(color)
        }
    }
}

/// Small tinted chip naming the device a row belongs to. Each device gets a
/// stable distinct color, so identical OS icons (two Macs) stay tellable apart.
struct DeviceChip: View {
    let device: Device

    private var shortName: String {
        device.name.count > 12 ? String(device.name.prefix(11)) + "…" : device.name
    }

    var body: some View {
        let tint = Theme.deviceTint(device)
        HStack(spacing: 3) {
            DeviceIcon(osID: device.osID, isLocal: device.isLocal, size: 8)
            Text(shortName)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 4)
        .frame(height: 15)
        .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 4))
        .fixedSize()
        .help(device.name)
    }
}

/// Device icon: sniffed-OS brand mark, falling back to a generic machine symbol.
struct DeviceIcon: View {
    let osID: String?
    let isLocal: Bool
    var size: CGFloat = 12

    var body: some View {
        if let resource = BrandIconLoader.osIcon(for: osID) {
            BrandIcon(resource: resource, size: size)
        } else {
            Image(systemName: isLocal ? "laptopcomputer" : "desktopcomputer")
                .font(.system(size: size - 0.5))
        }
    }
}
