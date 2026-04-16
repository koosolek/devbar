import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    let isPm2Available: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                Text("DevBar")
                    .font(.system(size: 28, weight: .semibold))
                    .padding(.bottom, 8)

                Text("Manage your dev servers\nfrom the menu bar.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)

            Spacer()

            if !isPm2Available {
                VStack(alignment: .leading, spacing: 8) {
                    Text("pm2 required")
                        .font(.system(size: 12, weight: .medium))

                    Text("Install pm2 to manage dev servers in the background:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        CopyableCommand("brew install pm2")
                        Text("or")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        CopyableCommand("npm i -g pm2")
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
            }

            HStack {
                Button(isPm2Available ? "Get Started" : "I've Installed pm2") {
                    hasCompletedOnboarding = true
                }
                .buttonStyle(OnboardingButtonStyle())
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
        .frame(width: 340, height: 240)
    }
}

private struct CopyableCommand: View {
    let command: String

    init(_ command: String) {
        self.command = command
    }

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        } label: {
            Text(command)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .help("Click to copy")
    }
}

struct OnboardingButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(colorScheme == .dark ? .black : .white)
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.7 : 1))
            )
    }
}
