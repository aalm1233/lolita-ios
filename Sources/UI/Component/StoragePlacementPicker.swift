import SwiftUI

struct StoragePlacementPicker: View {
    let rooms: [Location]
    let nodes: [StorageNode]
    @Binding var roomId: Int64?
    @Binding var nodeId: Int64?
    var body: some View {
        Picker("房间", selection: $roomId) {
            Text("未设置").tag(nil as Int64?)
            ForEach(rooms, id: \.id) { Text($0.name).tag($0.id as Int64?) }
        }.accessibilityIdentifier("storage-room")
        .onChange(of: roomId) { _, value in
            if nodeId != nil, nodes.first(where: { $0.id == nodeId })?.locationId != value { nodeId = nil }
        }
        if let roomId {
            Picker("柜架／层格", selection: $nodeId) {
                Text("仅房间").tag(nil as Int64?)
                ForEach(nodes.filter { $0.locationId == roomId }, id: \.id) { node in
                    Text(StorageTree.path(roomId: roomId, nodeId: node.id, rooms: rooms, nodes: nodes)).tag(node.id as Int64?)
                }
            }.accessibilityIdentifier("storage-node")
        }
    }
}
