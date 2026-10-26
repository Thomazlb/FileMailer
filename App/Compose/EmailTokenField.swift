import FileMailerCore
import SwiftUI

struct EmailTokenField: View {
    @Environment(\.locale) private var locale
    @Binding var addresses: [EmailAddress]
    @Binding var input: String
    var placeholder: LocalizedStringKey

    @FocusState private var isInputFocused: Bool

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(addresses) { address in
                    HStack(spacing: 5) {
                        Text(address.address)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)

                        Button {
                            addresses.removeAll { $0.normalized == address.normalized }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: FileMailerLocalization(languageIdentifier: locale.identifier)
                            .format("Delete %@", address.address)))
                    }
                    .font(.body)
                    .padding(.leading, 9)
                    .padding(.trailing, 6)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.12), in: Capsule())
                }

                TextField(
                    placeholder,
                    text: $input
                )
                .textFieldStyle(.plain)
                .accessibilityIdentifier("recipient-address-input")
                .focused($isInputFocused)
                .frame(minWidth: addresses.isEmpty ? 180 : 90)
                .onSubmit(commitInput)
                .onChange(of: input) { _, value in
                    commitSeparatedAddresses(in: value)
                }
            }
            .padding(.horizontal, 7)
            .frame(minHeight: 26)
        }
        .scrollIndicators(.hidden)
        .background(.white.opacity(0.055))
        .contentShape(Rectangle())
        .onTapGesture {
            isInputFocused = true
        }
        .accessibilityLabel(placeholder)
    }

    private func commitInput() {
        let pending = input
        input = ""
        addAddress(pending)
    }

    private func commitSeparatedAddresses(in value: String) {
        let separators = CharacterSet(charactersIn: ",;")
        guard value.rangeOfCharacter(from: separators) != nil else { return }

        let endsWithSeparator = value.last.map { $0 == "," || $0 == ";" } ?? false
        let components = value.components(separatedBy: separators)
        let valuesToCommit = endsWithSeparator
            ? components
            : Array(components.dropLast())
        valuesToCommit.forEach(addAddress)
        input = endsWithSeparator ? "" : (components.last ?? "")
    }

    private func addAddress(_ rawValue: String) {
        guard addresses.count < 50,
              let address = try? EmailAddress(rawValue),
              !addresses.contains(where: { $0.normalized == address.normalized })
        else {
            return
        }
        addresses.append(address)
    }
}
