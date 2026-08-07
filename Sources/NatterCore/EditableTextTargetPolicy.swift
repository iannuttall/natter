import Foundation

public enum EditableTextTargetPolicy {
    private static let editableRoles: Set<String> = [
        "AXComboBox",
        "AXTextArea",
        "AXTextField"
    ]

    public static func accepts(
        role: String?,
        selectedTextIsSettable: Bool
    ) -> Bool {
        role.map(editableRoles.contains) == true || selectedTextIsSettable
    }
}
