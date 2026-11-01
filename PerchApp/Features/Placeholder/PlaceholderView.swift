import SwiftUI

struct PlaceholderView: View {
    var body: some View {
        ZStack {
            Color(red: 11 / 255, green: 11 / 255, blue: 15 / 255)
            Text("Perch")
                .font(.system(size: 120, weight: .bold))
                .foregroundStyle(.white)
        }
        .ignoresSafeArea()
    }
}
