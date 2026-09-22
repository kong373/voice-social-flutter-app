# 当前共享UI规范与品牌边界

权威实现：`lib/core/design_system/app_theme.dart` 与 `runtime_surfaces.dart`；保留既有浅色社交/资产和深色房间方向，不增加平行组件体系。

| 项目 | 当前实现 |
|---|---|
| 可见品牌 | `AppBrand.name = 搭子岛`；原生显示名称有对应契约测试 |
| 浅色主色/正文/次文字 | `#6D57DF` / `#17213C` / `#596680` |
| 浅色页面/卡片/分隔 | `#F6F8FD` / `#FFFFFF` / `#E6EAF3` |
| 房间背景/正文/次文字 | `#08091B` / `#F9F7FF` / `#C0C3DC`；玻璃卡片保留原透明度 |
| 正文与标题 | social headline24、title20/16/14、body16/14/12；原页面局部层级按用途保留 |
| 反馈时长 | press140ms、navigation140ms、menu180ms、panel240ms；`AppMotion.forContext`读取减少动态偏好 |
| 进入/退出曲线 | 原 `easeOutCubic`；业务请求、租约、倒计时不受UI动效时长影响 |
| 命中区 | 主要操作目标48逻辑像素，受限布局至少44；小图标与命中区分离，不把全部视觉元素放大 |
| 间距 | 使用既有4/8尺度和组件内边距；收款说明16、字段12等经过实际页面验证，不整页改布局 |
| 文字颜色来源 | 子页面Theme建立前的外层context不能提供相反明暗的文字；必要位置显式用现有语义色 |
| 瞬态提示字体 | SnackBar沿用Theme创建时的fontFamily；不设置新系统字体，不改变错误内容 |
| 状态与数据 | 加载/错误/未知不伪装空值或成功；禁用必须保留原身份、权限、余额和请求代次判断 |

项目测试字体仍是既有固定来源Noto CJK子集，由仓库已有构建器生成并验证字符覆盖及来源哈希。不得分享系统字体或将测试缺字误判成生产设备缺字。
纯色正文对比目标4.5:1；该目标不等于所有图像背景、透明叠层和设备字体均已自动证明达标。实际审查范围见FINAL_REVIEW及图片索引。

## 品牌更名禁止触碰的标识

Android applicationId/namespace、iOS Bundle ID/签名/Entitlements、URL Scheme/Universal Links、Dart包名、IAP商品ID、内部voice-social标识和订单/幂等哈希均保持不变。远端协议、商店页面、厂商控制台和部署不属于本次客户端更名。

## 验证环境

Flutter3.44.7/Dart3.12.2，各独立目录自己的package_config；复用现有SDK和依赖。macOS Widget画面不充当Android/iOS设备截图或Linux golden证据。未修改共享SDK、原工作树、数据库或厂商配置。
