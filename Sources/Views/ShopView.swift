import SwiftUI

/// Between rounds, each player in turn spends their winnings.
struct ShopView: View {
    let game: Game
    let playerIndex: Int

    var body: some View {
        let player = game.players[playerIndex]
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(player.name)'s shop")
                        .font(.title.bold())
                        .foregroundStyle(player.color)
                    Text("Before round \(game.round + 1) of \(game.settings.rounds)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(player.money, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(.system(.title, design: .rounded).bold().monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.snappy, value: player.money)
                Button(action: game.finishShopping) {
                    PlateLabel(title: playerIndex + 1 < game.players.count ? "Done" : "Start round", systemImage: "checkmark")
                }
                .buttonStyle(.plate(player.color, .primary))
                    .padding(.leading, 12)
            }
            .padding(20)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                    ForEach(ShopItem.catalog) { item in
                        ShopItemCard(item: item, owned: player.inventory.count(of: item), canAfford: player.money >= item.price) {
                            game.buy(item)
                        }
                    }
                }
                .padding([.horizontal, .bottom], 20)
            }
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.14).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

struct ShopItemCard: View {
    let item: ShopItem
    let owned: Int
    let canAfford: Bool
    let onBuy: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.title2)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name).font(.headline).lineLimit(1).minimumScaleFactor(0.75)
                    if item.bundle > 1 {
                        Text("×\(item.bundle)").font(.caption.bold()).foregroundStyle(.orange)
                    }
                }
                Text(item.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                Text("Owned: \(owned)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button(action: onBuy) {
                Text(item.price, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(.system(size: 12, weight: .heavy).width(.condensed).monospacedDigit())
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: 64)
            }
            .buttonStyle(.plate(.green, size: .small))
            .disabled(!canAfford)
            .sensoryFeedback(.success, trigger: owned)
        }
        .padding(12)
        .frame(maxHeight: .infinity)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }
}
