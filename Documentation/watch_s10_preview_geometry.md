# WatchS10 表盘预览几何锚点（iPhone）

**目的**：`WatchS10Full` 资源上「黑玻璃」的视觉中心与矩形几何中心不完全重合。产品已标定 **光学中心**，后续凡在表盘图或表镜区域内叠加的 UI（自定义组件、时间、麦克风、表盘上方的装饰图等）**一律以统一几何为准**，避免各处复制魔法数字。

## 单一数据源（代码）

| 内容 | 位置 |
|------|------|
| 归一化表镜外接框、光学中心偏移、三角槽坐标轴与槽格尺寸 | `Shared/WatchFace/WatchS10PreviewGeometry.swift` |
| 表镜叠层、预览内布局 | `BolaBola iOS/Design/WatchS10MockupView.swift` |

### 关键 API

- **`WatchS10PreviewGeometry.screenRectInFull`**：黑屏区相对整图的归一化 `CGRect`（未含光学微调）。
- **`opticalCenterShiftXFractionOfScreen` / `opticalCenterShiftYFractionOfScreen`**：相对表镜几何中心的校准（量纲为表镜宽/高）。**改中心只改这里**，并视为与产品确认过的标定变更。
- **`opticalScreenCenterInFullImage(width:height:)`**：整图坐标系中的光学中心点；在 `Image("WatchS10Full")` 的 `GeometryReader` 里与 `geo.size` 同尺度使用。
- **`opticalCrossSegmentLength(screenWidth:screenHeight:)`**：十字与外接参考正方形边长。**`complicationSlotCornerHalfExtent(screenWidth:screenHeight:)`**：三角槽相对中心的半偏移（与十字同轴向，但另设上限，避免槽位出表镜）。**`complicationSlotCellWidth` / `complicationSlotCellHeight`**：单槽外接框。

### 以后新 UI 怎么接

1. 与现有预览 **同一层级**：在整表 `Image` 的 `overlay` 里用 `GeometryReader`，取 `w = geo.size.width`、`h = geo.size.height`，用 `opticalScreenCenterInFullImage(width:height:)` 作为锚点做 `offset` / `position`。
2. **仅表镜内**：可继续用「表镜局部坐标系」——叠层已与光学中心对齐，子视图以表镜 `frame` 的 center 为参考即可（与 `WatchS10MockupView` 内 `screenLabels` 一致）。
3. **勿**在业务视图里再写一套 `32/270` 或独立的 shift 数值；若手表端将来需要对齐同一比例，应从本枚举抽常量或共享同一换算。

## 与真机手表的关系

- iPhone 上为 **营销/配置预览**；真实手表 App 内布局见 `BolaBola Watch App`，比例不必像素级一致，但 **槽位语义**（左上/左下/右下）与 `WatchFaceSlotsConfiguration` 一致。
- 光学中心仅约束 **预览图** 与叠层对齐；系统表盘无法注入，产品说明见 PRD「自定义表盘」小节。

## 光学中心十字线

主界面预览默认显示，便于对照 `WatchS10PreviewGeometry` 光学中心；不需要时在 `WatchS10MockupView(showScreenCenterCrosshair:)` 传 `false`。
