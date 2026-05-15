import SwiftUI

// MARK: - App Mapping Rows

extension DashboardCategoriesView {
    func appMappingRow(_ source: SourceUsageStats) -> some View {
        let currentCategory = categoryManager.category(for: source.bundleIdentifier)
        let isOverridden = categoryManager.isUserOverridden(source.bundleIdentifier)

        return HStack(spacing: DashboardTheme.Spacing.md) {
            // App icon
            Group {
                if let image = source.nsImage() {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DashboardTheme.rule)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text(source.initials.uppercased())
                                .font(DashboardTheme.Fonts.sans(11, weight: .semibold))
                                .foregroundStyle(DashboardTheme.inkMuted)
                        )
                }
            }

            // App name
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DashboardTheme.Spacing.xs) {
                    Text(source.displayName)
                        .font(DashboardTheme.Fonts.sans(14, weight: .medium))
                        .foregroundStyle(DashboardTheme.ink)

                    if isOverridden {
                        Text("Custom")
                            .font(DashboardTheme.Fonts.sans(9, weight: .medium))
                            .foregroundStyle(DashboardTheme.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(DashboardTheme.accentLight)
                            )
                    }
                }

                Text(source.bundleIdentifier)
                    .font(DashboardTheme.Fonts.mono(10, weight: .regular))
                    .foregroundStyle(DashboardTheme.inkFaint)
            }

            Spacer()

            // Category picker
            categoryPicker(for: source, currentCategory: currentCategory, isOverridden: isOverridden)
        }
        .padding(DashboardTheme.Spacing.md)
    }

    func categoryPicker(
        for source: SourceUsageStats,
        currentCategory: CategoryDefinition,
        isOverridden: Bool
    ) -> some View {
        Menu {
            ForEach(categoryStore.categories, id: \.id) { category in
                Button {
                    categoryManager.setCategory(category, for: source.bundleIdentifier)
                } label: {
                    HStack {
                        Image(systemName: category.icon)
                        Text(category.displayName)
                        if currentCategory.id == category.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            if isOverridden {
                Divider()
                Button("Reset to Default") {
                    categoryManager.resetToDefault(for: source.bundleIdentifier)
                }
            }
        } label: {
            HStack(spacing: DashboardTheme.Spacing.xs) {
                Image(systemName: currentCategory.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(currentCategory.color)

                Text(currentCategory.displayName)
                    .font(DashboardTheme.Fonts.sans(12, weight: .medium))
                    .foregroundStyle(DashboardTheme.ink)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DashboardTheme.inkMuted)
            }
            .padding(.horizontal, DashboardTheme.Spacing.sm)
            .padding(.vertical, DashboardTheme.Spacing.xs + 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(DashboardTheme.cardBgAlt)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(DashboardTheme.rule, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
    }
}
