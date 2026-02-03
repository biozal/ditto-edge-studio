import SwiftUI

struct MongoSidebarView: View {
    @Binding var mongoCollections: [String]
    var body: some View {
        VStack{
            Text("MongoDB Collections")
                .font(.title2)
                .foregroundColor(.primary)
            if (mongoCollections.isEmpty) {
                Text("No collections found.")
            } else {
                List(mongoCollections, id: \.self){ collection in
                    Text(collection)
                        .onTapGesture {
                            
                        }
                    Divider()
                }
            }
        }
    }
}

#Preview {
    MongoSidebarView(
        mongoCollections: .constant([
            "movies",
            "users",
            "products"
        ]),
    )
}
