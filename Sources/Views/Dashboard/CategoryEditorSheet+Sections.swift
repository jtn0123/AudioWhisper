import SwiftUI

// MARK: - Editor Sections

extension CategoryEditorSheet {
    var identitySection: some View {
        formSection("Identity") {
            formField("Display Name") {
                TextField("e.g. Terminal", text: $displayName)
                    .textFieldStyle(.plain)
                    .font(DashboardTheme.Fonts.sans(14, weight: .regular))
                    .padding(12)
                    .background(DashboardTheme.pageBg, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(DashboardTheme.rule, lineWidth: 1)
                    )
            }

            formField("Identifier") {
                TextField("e.g. terminal", text: $identifier)
                    .textFieldStyle(.plain)
                    .font(DashboardTheme.Fonts.mono(14, weight: .regular))
                    .padding(12)
                    .background(DashboardTheme.pageBg, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(DashboardTheme.rule, lineWidth: 1)
                    )
                    .disabled(isSystem)
                    .opacity(isSystem ? 0.6 : 1)

                if isSystem {
                    Text("System category identifiers cannot be changed")
                        .font(DashboardTheme.Fonts.sans(11, weight: .regular))
                        .foregroundStyle(DashboardTheme.inkFaint)
                }
            }
        }
    }

    var appearanceSection: some View {
        formSection("Appearance") {
            HStack(alignment: .top, spacing: DashboardTheme.Spacing.xl) {
                formField("Icon") {
                    HStack(spacing: DashboardTheme.Spacing.sm) {
                        Image(systemName: icon.isEmpty ? "questionmark" : icon)
                            .font(.system(size: 16))
                            .foregroundStyle(accentColor)
                            .frame(width: 40, height: 40)
                            .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                        TextField("SF Symbol", text: $icon)
                            .textFieldStyle(.plain)
                            .font(DashboardTheme.Fonts.mono(13, weight: .regular))
                            .padding(10)
                            .frame(width: 140)
                            .background(DashboardTheme.pageBg, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(DashboardTheme.rule, lineWidth: 1)
                            )
                    }
                }

                formField("Color") {
                    HStack(spacing: DashboardTheme.Spacing.sm) {
                        ColorPicker("", selection: $accentColor, supportsOpacity: false)
                            .labelsHidden()

                        Text(accentColor.hexString() ?? "#000000")
                            .font(DashboardTheme.Fonts.mono(12, weight: .regular))
                            .foregroundStyle(DashboardTheme.inkMuted)
                    }
                }

                Spacer()
            }
        }
    }

    var correctionSection: some View {
        formSection("Correction Behavior") {
            formField("Description") {
                TextField("Brief summary for category list", text: $promptDescription, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(DashboardTheme.Fonts.sans(13, weight: .regular))
                    .lineLimit(2...3)
                    .padding(12)
                    .background(DashboardTheme.pageBg, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(DashboardTheme.rule, lineWidth: 1)
                    )
            }

            formField("Prompt Template") {
                TextEditor(text: $promptTemplate)
                    .font(DashboardTheme.Fonts.mono(12, weight: .regular))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 160)
                    .background(DashboardTheme.pageBg, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(DashboardTheme.rule, lineWidth: 1)
                    )

                Text("Instructions sent to the correction model for this category")
                    .font(DashboardTheme.Fonts.sans(11, weight: .regular))
                    .foregroundStyle(DashboardTheme.inkFaint)
            }
        }
    }
}
