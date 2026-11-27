import SwiftUI
import UIKit

/// UIKit owns the interactive move and edge autoscroll. Only the grip starts
/// a move, leaving the song itself available for playback and its context menu.
struct UpcomingQueueList: UIViewRepresentable {
    @Environment(PlayerStore.self) var player
    @Environment(DownloadStore.self) var downloads
    @Environment(AppSettings.self) var settings
    @Environment(\.locale) var locale
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    let entries: [UpcomingQueueEntry]
    let headerInset: CGFloat
    let indicatorInset: CGFloat
    let onScroll: (CGFloat) -> Void
    let onReordering: (Bool) -> Void
    let onMove: (IndexSet, Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICollectionView {
        var layout = UICollectionLayoutListConfiguration(appearance: .plain)
        layout.backgroundColor = .clear
        layout.showsSeparators = false
        let list = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: layout))
        list.backgroundColor = .clear
        list.overrideUserInterfaceStyle = .dark
        list.contentInsetAdjustmentBehavior = .never
        list.indicatorStyle = .white
        list.delegate = context.coordinator
        list.dataSource = context.coordinator
        list.register(UICollectionViewListCell.self, forCellWithReuseIdentifier: "queue")
        context.coordinator.list = list
        return list
    }

    func updateUIView(_ list: UICollectionView, context: Context) {
        let coordinator = context.coordinator
        let previous = coordinator.parent
        coordinator.parent = self
        list.verticalScrollIndicatorInsets.top = indicatorInset
        if entries != previous.entries || locale != previous.locale || headerInset != previous.headerInset {
            coordinator.refreshEntries()
        }
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
        var parent: UpcomingQueueList
        private var displayedEntries: [UpcomingQueueEntry]
        weak var list: UICollectionView?
        private var movingCell: UICollectionViewCell?
        private var touchOffset: CGFloat = 0

        init(_ parent: UpcomingQueueList) {
            self.parent = parent
            displayedEntries = parent.entries
        }

        func refreshEntries() {
            finishMove(cancelled: true)
            displayedEntries = parent.entries
            list?.reloadData()
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            1 + max(displayedEntries.count, 1)
        }

        func collectionView(_ list: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = list.dequeueReusableCell(withReuseIdentifier: "queue", for: indexPath) as! UICollectionViewListCell
            cell.automaticallyUpdatesBackgroundConfiguration = false
            cell.isOpaque = false
            cell.backgroundConfiguration = .clear()
            cell.accessories = []
            if indexPath.item == 0 {
                cell.contentConfiguration = UIHostingConfiguration {
                    Text("ui.player.continue_playing")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, parent.headerInset + 14)
                        .padding(.bottom, 10)
                        .environment(\.locale, parent.locale)
                }.margins(.all, 0)
            } else if displayedEntries.isEmpty {
                cell.contentConfiguration = UIHostingConfiguration {
                    ContentUnavailableView("ui.player.no_up_next", systemImage: "list.bullet")
                        .padding(.vertical, 24)
                        .environment(\.locale, parent.locale)
                }.margins(.all, 0)
            } else {
                let entry = displayedEntries[indexPath.item - 1]
                // The menu preview is hosted outside the cell; size it from the presenting window.
                let previewWidth = { [weak list] in
                    list?.window?.safeAreaLayoutGuide.layoutFrame.width ?? list?.bounds.width ?? 0
                }
                cell.contentConfiguration = UIHostingConfiguration {
                    NowPlayingQueueRow(entry: entry, previewWidth: previewWidth)
                        .environment(parent.player)
                        .environment(parent.downloads)
                        .environment(parent.settings)
                        .environment(\.locale, parent.locale)
                }.margins(.all, 0)
                let grip = UIImageView(image: UIImage(systemName: "line.3.horizontal"))
                grip.frame.size = CGSize(width: 44, height: 44)
                grip.contentMode = .center
                grip.tintColor = .tertiaryLabel
                grip.isUserInteractionEnabled = true
                grip.isAccessibilityElement = true
                grip.accessibilityLabel = entry.song.name
                grip.accessibilityCustomActions = [(-1, "ui.queue.move_up"), (1, "ui.queue.move_down")].compactMap { step, key in
                    guard displayedEntries.indices.contains(indexPath.item - 1 + step) else { return nil }
                    return UIAccessibilityCustomAction(name: L10n.string(key)) { [weak self] _ in
                        guard let self, let from = self.parent.entries.firstIndex(where: { $0.id == entry.id }),
                              self.parent.entries.indices.contains(from + step) else { return false }
                        self.parent.onMove(IndexSet(integer: from), step < 0 ? from - 1 : from + 2)
                        return true
                    }
                }
                let press = UILongPressGestureRecognizer(target: self, action: #selector(handleGrip(_:)))
                press.minimumPressDuration = 0
                grip.addGestureRecognizer(press)
                cell.accessories = [.customView(configuration: .init(customView: grip, placement: .trailing(), reservedLayoutWidth: .custom(44)))]
            }
            return cell
        }

        @objc private func handleGrip(_ gesture: UILongPressGestureRecognizer) {
            guard let list else { return }
            let touch = gesture.location(in: list)
            switch gesture.state {
            case .began:
                guard let path = list.indexPathForItem(at: touch), path.item > 0,
                      let cell = list.cellForItem(at: path) else { return }
                var lifted = UIBackgroundConfiguration.clear()
                lifted.backgroundColor = UIColor.white.withAlphaComponent(0.12)
                lifted.cornerRadius = 10
                cell.backgroundConfiguration = lifted
                guard list.beginInteractiveMovementForItem(at: path) else {
                    cell.backgroundConfiguration = .clear()
                    return
                }
                movingCell = cell
                touchOffset = cell.center.y - touch.y
                setExpanded(true)
            case .changed:
                guard movingCell != nil else { return }
                list.updateInteractiveMovementTargetPosition(CGPoint(x: list.bounds.midX, y: touch.y + touchOffset))
            case .ended: finishMove(cancelled: false)
            case .cancelled, .failed: finishMove(cancelled: true)
            default: break
            }
        }

        func finishMove(cancelled: Bool) {
            guard let cell = movingCell else { return }
            movingCell = nil
            if cancelled { list?.cancelInteractiveMovement() } else { list?.endInteractiveMovement() }
            cell.backgroundConfiguration = .clear()
            setExpanded(false)
        }

        private func setExpanded(_ active: Bool) {
            withAnimation(parent.reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                parent.onReordering(active)
            }
        }

        func collectionView(_ list: UICollectionView, canMoveItemAt path: IndexPath) -> Bool {
            path.item > 0 && !displayedEntries.isEmpty
        }

        func collectionView(_ list: UICollectionView, targetIndexPathForMoveOfItemFromOriginalIndexPath original: IndexPath,
                            atCurrentIndexPath current: IndexPath, toProposedIndexPath proposed: IndexPath) -> IndexPath {
            IndexPath(item: max(1, proposed.item), section: 0)
        }

        func collectionView(_ list: UICollectionView, moveItemAt source: IndexPath, to destination: IndexPath) {
            let from = source.item - 1
            let to = destination.item - 1
            guard from != to, parent.entries.indices.contains(from), parent.entries.indices.contains(to),
                  parent.player.unplayedQueueIndices == parent.entries.map(\.queueIndex),
                  parent.entries.allSatisfy({ parent.player.queue[$0.queueIndex].id == $0.song.id }) else { return }
            let movedEntry = displayedEntries.remove(at: from)
            displayedEntries.insert(movedEntry, at: to)
            parent.onMove(IndexSet(integer: from), to > from ? to + 1 : to)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            parent.onScroll(scrollView.contentOffset.y)
        }
    }
}
