//
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/23/25.
//

import DittoPresenceViewer
import DittoSwift
import SwiftUI

struct ToolsErrorView: View{

    var body: some View {
        ContentUnavailableView(
            "Error",
            systemImage: "exclamationmark.triangle.fill",
            description: Text(
                "Unable to load tools - selected Ditto instance is not available.  Close and restart the app."
            )
        )
    }
}
