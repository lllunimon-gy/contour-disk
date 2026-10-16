import SwiftUI
import Contour

@main struct ContourExample: App { var body: some Scene { WindowGroup { ContentView() } } }
struct ContentView: View {
    @State private var message = "先生成示例数据，再扫描"
    @State private var baseline: DiskSnapshot?
    @State private var latest: DiskSnapshot?
    @State private var cancellation = ScanCancellation()
    @State private var busy = false
    private let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ContourExample")
    var body: some View {
        NavigationView { List {
            Text(message).textSelection(.enabled)
            Button("添加一批模拟文件") { generate() }.disabled(busy)
            Button("扫描") { scan() }.disabled(busy)
            Button("取消") { cancellation.cancel() }.disabled(!busy)
            Button("保存为基线") { baseline = latest; message = "已保存基线" }.disabled(latest == nil || busy)
            Button("与基线比较") {
                guard let before = baseline, let after = latest else { return }
                do {
                    let d = try SnapshotDifference(before: before, after: after)
                    message = "新增 \(d.added.count)，删除 \(d.removed.count)，变化 \(d.changed.count)"
                } catch { message = String(describing: error) }
            }.disabled(baseline == nil || latest == nil || busy)
        }.navigationTitle("Contour · gy") }
    }
    private func generate() {
        busy = true
        let directory = root
        Task {
            let result = await Task.detached { () -> String in
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    for n in 1...256 {
                        try Data(repeating: 0x61, count: n * 16).write(to: directory.appendingPathComponent("\(UUID().uuidString).bin"))
                    }
                    return "已添加 256 个文件"
                } catch { return String(describing: error) }
            }.value
            message = result; busy = false
        }
    }
    private func scan() {
        busy = true; cancellation = ScanCancellation()
        let directory = root, token = cancellation
        Task {
            let result = await Task.detached { Result { try DiskScanner().scan(root: directory, cancellation: token) } }.value
            switch result {
            case .success(let s):
                latest = s
                message = "\(s.files.count) 个文件\n逻辑大小 \(s.logicalBytes) B\n已分配 \(s.allocatedBytes) B\n取消：\(s.cancelled)，错误：\(s.issues.count)"
            case .failure(let e): message = String(describing: e)
            }
            busy = false
        }
    }
}
