# R02 实名补交与入会引导

Backend合同：V67 / f5f9fb8973fc88c1fe740972caae5bdb1bf16d92，主集成47bbd82。
用户已确认注册不判断年龄，实名阶段判断；本批没有注册生日或年龄确认项。

服务端实名状态必须包含真实bool needsAgeResubmission/canSubmit，且与status/statusCode一致。
纯解析文件与测试来自既有ChatGPT协作任务，主机审阅并实际接入BackendAccountComplianceRepository；
仍保留原providerStatus/reviewStatus/reviewMode/providerInvocation的第一方人工审核校验。
缺字段、类型错误或矛盾返回protocol错误，不推断为已完成/允许提交。

旧VERIFIED缺DOB的账号显示“需补交实名资料”和提交表单；现有完整VERIFIED/PENDING不显示表单。
表单仍受accountUsable、青少年模式、身份代际和服务端最终权限约束。
支持后端既有15/18位证件输入；本地只校验输入形状，真实日历/checksum/18岁和人工审核由后端裁决。
缺年龄资料的入会预检不发申请POST，先引导补交；返回公会页不自动发申请。

RED：两项旧VERIFIED补交/入会widget实际失败；HTTP snapshot原来忽略needsAgeResubmission实际失败。
GREEN：8个相关文件111/111测试通过；全Flutter analyze零问题；12个改动Dart文件format/diff-check通过。
第一轮110PASS/1FAIL为旧夹具从APPROVED切到REJECTED未同步canSubmit，已修夹具保留原状态断言。
原敏感写身份、重复提交、失败重试和账号ABA测试未删除或跳过。

独立审查补充：历史PENDING写回执没有上述两个新bool，不能因此陷入不断重放POST的恢复循环。
仅对两个字段均缺失且原有PENDING/statusCode/provider审核元组仍合法的旧回执兼容；
随后以当前身份GET严格读取最新状态，不用旧回执推断当前年龄/入会资格。
该GET失败时保留原意图，后续只重试读取，不换key重新提交。
新增21项HTTP与身份延迟/ABA回归，两个指定真实场景先RED；最终相关132/132 PASS、全analyze零问题。
主任务已逐项复核这两文件补丁；旧receipt部分缺字段/矛盾/provider错误仍拒绝。

QA contract server只同步上述布尔字段，不把Mock结果用作真实后端或四设备验收。
本批未启动Android/iOS设备、未部署、未调用实名厂商，不代表最终RELEASE_READY。
