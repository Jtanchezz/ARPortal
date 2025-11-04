import SwiftUI

struct ContentView: View {
    @State private var showHelp = true

    var body: some View {
        ZStack(alignment: .top) {
            PortalARView()
                .edgesIgnoringSafeArea(.all)

            if showHelp {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Portal AR")
                        .font(.title2)
                        .bold()
                    Text("1. Mueve el iPhone para detectar un plano.")
                    Text("2. Toca la pantalla para colocar el portal.")
                    Text("3. Camina a través del portal para entrar al cuarto.")
                    Button(action: { withAnimation { showHelp = false } }) {
                        Text("Entendido")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.top, 44)
                .padding(.horizontal)
            }
        }
    }
}

#Preview {
    ContentView()
}
