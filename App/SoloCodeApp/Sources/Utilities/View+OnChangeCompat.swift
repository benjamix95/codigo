import SwiftUI

private struct OnChangeCompatModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let action: (Value, Value) -> Void
    @State private var previousValue: Value?

    func body(content: Content) -> some View {
        content
            .onAppear {
                previousValue = value
            }
            .onChange(of: value) { newValue in
                let oldValue = previousValue ?? newValue
                action(oldValue, newValue)
                previousValue = newValue
            }
    }
}

extension View {
    func onChangeCompat<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value, Value) -> Void
    ) -> some View {
        modifier(OnChangeCompatModifier(value: value, action: action))
    }
}
