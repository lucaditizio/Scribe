import SwiftUI

struct DashboardHeaderView: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        EmptyView()
    }
}

#Preview {
    DashboardHeaderView()
        .preferredColorScheme(.dark)
}
