import SwiftUI
import AppKit

internal struct CategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let categoryStore: CategoryStore
    let originalCategory: CategoryDefinition?
    let onSave: (CategoryDefinition) -> Void
    let onDelete: (() -> Void)?
    
    @State var displayName: String
    @State var identifier: String
    @State var icon: String
    @State var accentColor: Color
    @State var promptDescription: String
    @State var promptTemplate: String
    @State private var validationError: String?

    private let isNewCategory: Bool
    let isSystem: Bool
    
    init(
        category: CategoryDefinition?,
        categoryStore: CategoryStore = .shared,
        onSave: @escaping (CategoryDefinition) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.categoryStore = categoryStore
        self.originalCategory = category
        self.onSave = onSave
        self.onDelete = onDelete
        self.isNewCategory = category == nil
        self.isSystem = category?.isSystem ?? false
        
        let cat = category ?? CategoryDefinition(
            id: "new-category",
            displayName: "New Category",
            icon: "sparkles",
            colorHex: "#888888",
            promptDescription: "Describe this category's purpose",
            promptTemplate: CategoryDefinition.fallback.promptTemplate,
            isSystem: false
        )
        
        _displayName = State(initialValue: cat.displayName)
        _identifier = State(initialValue: cat.id)
        _icon = State(initialValue: cat.icon)
        _accentColor = State(initialValue: cat.color)
        _promptDescription = State(initialValue: cat.promptDescription)
        _promptTemplate = State(initialValue: cat.promptTemplate)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
            ScrollView {
                VStack(alignment: .leading, spacing: DashboardTheme.Spacing.xl) {
                    previewCard
                    identitySection
                    appearanceSection
                    correctionSection
                    
                    if let error = validationError {
                        errorBanner(error)
                    }
                    
                    actionButtons
                }
                .padding(DashboardTheme.Spacing.xl)
            }
        }
        .frame(width: 560, height: 680)
        .background(DashboardTheme.pageBg)
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Text(isNewCategory ? "New Category" : "Edit Category")
                .font(DashboardTheme.Fonts.serif(20, weight: .semibold))
                .foregroundStyle(DashboardTheme.ink)
            
            Spacer()
            
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(DashboardTheme.inkMuted)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, DashboardTheme.Spacing.xl)
        .padding(.vertical, DashboardTheme.Spacing.md)
        .background(DashboardTheme.cardBg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DashboardTheme.rule).frame(height: 1)
        }
    }
    
    // MARK: - Preview Card
    
    private var previewCard: some View {
        HStack(spacing: DashboardTheme.Spacing.md) {
            Image(systemName: icon.isEmpty ? "questionmark" : icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(accentColor, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: accentColor.opacity(0.4), radius: 8, y: 4)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName.isEmpty ? "Category Name" : displayName)
                    .font(DashboardTheme.Fonts.serif(18, weight: .semibold))
                    .foregroundStyle(DashboardTheme.ink)
                
                Text(identifier.isEmpty ? "identifier" : identifier)
                    .font(DashboardTheme.Fonts.mono(12, weight: .regular))
                    .foregroundStyle(DashboardTheme.inkMuted)
            }
            
            Spacer()
            
            if isSystem {
                Text("System")
                    .font(DashboardTheme.Fonts.sans(10, weight: .semibold))
                    .foregroundStyle(DashboardTheme.inkMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DashboardTheme.rule, in: Capsule())
            }
        }
        .padding(DashboardTheme.Spacing.lg)
        .background(DashboardTheme.cardBg, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(DashboardTheme.rule, lineWidth: 1)
        )
    }
    
    // MARK: - Actions
    
    private var actionButtons: some View {
        HStack(spacing: DashboardTheme.Spacing.md) {
            Button {
                save()
            } label: {
                Text("Save Category")
                    .font(DashboardTheme.Fonts.sans(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(DashboardTheme.accent, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(displayName.isEmpty)
            .opacity(displayName.isEmpty ? 0.5 : 1)
            
            if !isNewCategory && !isSystem, let onDelete {
                Button {
                    onDelete()
                    dismiss()
                } label: {
                    Text("Delete")
                        .font(DashboardTheme.Fonts.sans(14, weight: .medium))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
    }
    
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(DashboardTheme.Fonts.sans(13, weight: .medium))
                .foregroundStyle(DashboardTheme.ink)
        }
        .padding(DashboardTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Helpers
    
    func formSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.md) {
            Text(title.uppercased())
                .font(DashboardTheme.Fonts.sans(10, weight: .bold))
                .foregroundStyle(DashboardTheme.inkMuted)
                .tracking(1.2)
            
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
                content()
            }
            .padding(DashboardTheme.Spacing.lg)
            .background(DashboardTheme.cardBg, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(DashboardTheme.rule, lineWidth: 1)
            )
        }
    }
    
    func formField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(DashboardTheme.Fonts.sans(12, weight: .semibold))
                .foregroundStyle(DashboardTheme.ink)
            
            content()
        }
    }
    
    private func save() {
        // Validate
        let trimmedId = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIcon = icon.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty {
            validationError = "Display name is required"
            return
        }

        // System categories keep their original identifier; only validate the
        // identifier field when the user is allowed to edit it.
        if !isSystem && trimmedId.isEmpty {
            validationError = "Identifier is required"
            return
        }

        // Check for duplicate ID (only if ID changed or new category)
        let originalId = originalCategory?.id
        if trimmedId != originalId && categoryStore.containsCategory(withId: trimmedId) {
            validationError = "A category with this identifier already exists"
            return
        }

        // Reject icon strings that aren't valid SF Symbols so the saved category
        // doesn't render as a blank glyph. An empty icon is allowed because the
        // downstream UI falls back to "questionmark".
        if !trimmedIcon.isEmpty,
           NSImage(systemSymbolName: trimmedIcon, accessibilityDescription: nil) == nil {
            validationError = "Icon must be a valid SF Symbol name (e.g. star.fill)"
            return
        }

        let category = CategoryDefinition(
            id: isSystem ? (originalCategory?.id ?? trimmedId) : trimmedId,
            displayName: trimmedName,
            icon: trimmedIcon,
            colorHex: accentColor.hexString() ?? "#888888",
            promptDescription: promptDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            promptTemplate: promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines),
            isSystem: isSystem
        )

        onSave(category)
        dismiss()
    }
}

// MARK: - Testable Helpers
extension CategoryEditorSheet {
    /// Validation result for form fields
    enum ValidationResult: Equatable {
        case valid
        case emptyName
        case duplicateId
    }

    /// Validates the category form fields
    static func testableValidate(
        displayName: String,
        identifier: String,
        originalId: String?,
        existingIds: Set<String>
    ) -> ValidationResult {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty {
            return .emptyName
        }

        let trimmedId = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedId != originalId && existingIds.contains(trimmedId) {
            return .duplicateId
        }

        return .valid
    }

    /// Returns whether this is a new category (create mode)
    static func testableIsNewCategory(category: CategoryDefinition?) -> Bool {
        category == nil
    }

    /// Returns whether identifier editing should be disabled
    static func testableIsIdentifierDisabled(isSystem: Bool) -> Bool {
        isSystem
    }

    /// Returns whether delete button should be shown
    static func testableShowsDeleteButton(isNewCategory: Bool, isSystem: Bool, hasDeleteHandler: Bool) -> Bool {
        !isNewCategory && !isSystem && hasDeleteHandler
    }

    /// Returns whether save button should be disabled
    static func testableIsSaveDisabled(displayName: String) -> Bool {
        displayName.isEmpty
    }

    /// Default values for a new category
    struct DefaultCategoryValues {
        let id: String
        let name: String
        let icon: String
        let colorHex: String
        let description: String
    }

    /// Normalized category fields prepared for saving
    struct NormalizedCategoryFields {
        let id: String
        let name: String
        let icon: String
        let desc: String
        let template: String
    }

    /// Creates default values for a new category
    static func testableDefaultCategoryValues() -> DefaultCategoryValues {
        DefaultCategoryValues(
            id: "new-category",
            name: "New Category",
            icon: "sparkles",
            colorHex: "#888888",
            description: "Describe this category's purpose"
        )
    }

    /// Trims whitespace from all category fields for saving
    static func testableNormalizeForSave(
        identifier: String,
        displayName: String,
        icon: String,
        promptDescription: String,
        promptTemplate: String
    ) -> NormalizedCategoryFields {
        NormalizedCategoryFields(
            id: identifier.trimmingCharacters(in: .whitespacesAndNewlines),
            name: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: icon.trimmingCharacters(in: .whitespacesAndNewlines),
            desc: promptDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            template: promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
