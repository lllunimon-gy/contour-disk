# Contour

给一个目录建立磁盘快照，解释空间分布，再比较下一次扫描发生了什么。
扫描只读；不把“占了多少空间”直接等同于“可以释放多少空间”。

作者：**gy** · MIT · iOS 15+ / macOS 12+ · Swift + Objective-C

## 运行

Mac：`swift test`。Xcode：打开 `Examples/ContourExample.xcodeproj` 并运行。
示例在自己的缓存目录造数据，可扫描、取消、保存基线和比较；不接触其他业务目录。

```swift
// 在后台队列运行；progress 也在该队列回调。
let token = ScanCancellation()
let snapshot = try DiskScanner().scan(root: directory, cancellation: token)
print(snapshot.logicalBytes, snapshot.allocatedBytes)
let report = try snapshot.json()
```

## 报告包含什么

文件逻辑长度、系统报告的已分配大小、inode 身份、修改时间、扩展名和一级目录汇总、
Top N 文件、失败项、跳过的符号链接数、起止时间及是否取消。
同一设备上的硬链接只计一次总量，文件列表仍保留每条路径。

快照比较按路径匹配，并考虑大小、修改时间和身份。不计算内容哈希，不能识别保留元数据的内容改写。
不完整快照禁止进行精确差异比较；重命名呈现为删除加新增。

## 边界

这是应用自有目录的诊断工具，不是对抗恶意并发路径替换的安全沙箱。
根目录先解析符号链接；后代链接跳过。扫描期间文件可以变化，结果不是瞬时事务快照。
APFS 克隆/共享块无法由这些属性准确去重，allocatedBytes 不等于删除后回收空间。
结果占用 O(文件数) 内存；超大目录的流式输出列为后续练习。

[设计](Documentation/design.md) · [实验](Documentation/experiments.md) · [验证](Documentation/validation.md)
