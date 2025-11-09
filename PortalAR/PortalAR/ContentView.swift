import SwiftUI

struct ContentView: View {
    @StateObject private var experienceState = PortalExperienceState()
    @State private var showHelp = true

    var body: some View {
        ZStack(alignment: .top) {
            PortalARView(experienceState: experienceState)
                .edgesIgnoringSafeArea(.all)

            if showHelp {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Portal AR")
                        .font(.title2)
                        .bold()
                    Text("1. Escanea el espacio hasta que veas el círculo turquesa.")
                    Text("2. Toca la pantalla para abrir el portal en ese punto.")
                    Text("3. Atraviesa la puerta para entrar al showroom.")
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

            if experienceState.showInsideHint {
                PortalStateHint(isInside: experienceState.isInsidePortal) {
                    withAnimation {
                        experienceState.dismissHint()
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, showHelp ? 220 : 72)
                .padding(.horizontal)
            }
        }
    }
}

#Preview {
    ContentView()
}

private struct PortalStateHint: View {
    let isInside: Bool
    let dismissAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isInside ? "figure.walk.motion" : "viewfinder.circle")
                .font(.title3)
                .foregroundStyle(.white)
                .padding(8)
                .background(Color.accentColor.opacity(0.6), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(isInside ? "Estás dentro del showroom" : "Cruza el portal para entrar")
                    .font(.headline)
                Text(isInside ? "Muévete con calma, las paredes del portal te mantendrán dentro."
                               : "Alinea tu cámara con la puerta y avanza para activar la experiencia.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: dismissAction) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
