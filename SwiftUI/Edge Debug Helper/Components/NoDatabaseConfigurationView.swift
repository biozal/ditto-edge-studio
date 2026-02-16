import SwiftUI

/// Empty state view displayed when no database configurations exist.
/// Provides user guidance and links to documentation.
struct NoDatabaseConfigurationView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with icon and title (centered)
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.orange)

                Text("No Database Configurations")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)

            // Description paragraphs (left-aligned)
            VStack(alignment: .leading, spacing: 20) {
                Text("No Ditto databases have been registered. This application requires you to have a Ditto Portal account and a Database setup in the Ditto portal.")

                Text("Click the plus button to register your first Ditto Database with Ditto Edge Studio. Note you must get the database configuration information from the [Ditto portal](https://portal.ditto.live).")
                    .fixedSize(horizontal: false, vertical: true)

                Text("Don't have a Ditto Portal account? You can learn how to create one from [here](https://docs.ditto.live/cloud/portal/creating-a-ditto-account).")
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                // Learning path info panel
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 16))

                    Text("🧑‍🎓 Want to learn Ditto? Ditto Edge Studio has a built in Learning Path that can help you understand Ditto better.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)

                Spacer()
            }
            .font(.default)
            .foregroundColor(.primary)
            .tint(.blue)
        }
        .frame(maxWidth: 600)
        .padding(40)
    }
}

#Preview {
    NoDatabaseConfigurationView()
}
