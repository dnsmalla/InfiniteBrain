import SwiftUI

struct QueryView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Query the brain")
                .font(.title2.bold())
            Text("Coming next: ask a question, the brain runs summary-first scoped retrieval over the vault.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
