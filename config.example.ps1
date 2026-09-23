# 挂件配置模板 —— 复制本文件为 config.ps1 并填入你自己的值 (config.ps1 已被 .gitignore 排除)
# 注意: config.ps1 必须保存为 UTF-8 BOM (跑一次 setup.ps1 自动修复)

$Cfg = @{
    # GLM 开放平台 API Key (https://open.bigmodel.cn 控制台获取); 同一把 Key 同时用于:
    #   1) 配额查询 (open.bigmodel.cn/api/monitor/usage/quota/limit)
    #   2) Anthropic 研究标题翻译 (glm-4-flash)
    Key     = '在这里填入你的GLM_API_Key'

    Url     = 'https://open.bigmodel.cn/api/monitor/usage/quota/limit'
    Minutes = 1     # GLM 额度刷新间隔(分钟)

    TrackW  = 340   # 进度条像素宽

    # B站关注列表: uid = UP主空间页地址里那串数字; 照此格式追加/删减
    # 注意: 某些 UP 的空间设置了"登录可见", 需要桥接浏览器保持B站登录态才能拉到
    BiliUps = @(
        @{ uid = '520155988';  name = '示例UP主一' },
        @{ uid = '90183256';   name = '示例UP主二' }
    )

    BiliTickMin = 144         # B站全量核对一轮的间隔(分钟), 一轮 = 列表全部 UP 各核对一次
    AnthMin     = 1440        # Anthropic 研究刷新间隔(分钟), 1440 = 每天一次
}
