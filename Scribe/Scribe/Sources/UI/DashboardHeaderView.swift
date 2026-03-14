import SwiftUI

struct DashboardHeaderView: View {
    @Environment(\.colorScheme) var colorScheme
    // In Phase 1, these are mock values for the UI aesthetic
    var minutesUsed: Int = 142
    var minutesTotal: Int = 300
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pro Plan")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            HStack(alignment: .lastTextBaseline) {
                Text("\(minutesUsed)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("/ \(minutesTotal) mins this month")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.accentGray)
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary)
                        .frame(width: geometry.size.width * CGFloat(minutesUsed) / CGFloat(minutesTotal), height: 8)
                }
            }
            .frame(height: 8)
        }
        .scribeCardStyle(scheme: colorScheme)
        .padding(.horizontal)
        .padding(.top)
    }
}

#Preview {
    DashboardHeaderView()
        .preferredColorScheme(.dark)
}
