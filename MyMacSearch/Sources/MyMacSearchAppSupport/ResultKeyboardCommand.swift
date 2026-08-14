public enum ResultKeyboardCommand: Equatable, Sendable {
    case quickLook

    public static func resolve(
        characters: String,
        hasModifiers: Bool
    ) -> ResultKeyboardCommand? {
        guard !hasModifiers, characters == " " else { return nil }
        return .quickLook
    }
}
