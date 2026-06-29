---
# 彻底隐藏首页的侧边菜单和右侧大纲，腾出巨幕空间
hide:
  - navigation
  - toc
---

<style>
/* =========================================
   修复：抹除全局 CSS 在首页留下的侧边栏空白，强制绝对居中
   ========================================= */
body .md-content {
  margin-left: 0 !important;
}
.md-grid {
  max-width: 60rem !important; /* 限制首页最大宽度，让巨幕更聚拢、更好看 */
}

/* 1. 强制 PC 端网格为完美的 2x2 对称布局，治愈强迫症 */
@media screen and (min-width: 60em) {
  .md-typeset .grid.cards.symmetric-2x2 {
    grid-template-columns: repeat(2, 1fr) !important;
  }
}

/* 2. 手写大厂风巨幕 (Hero) 样式 */
.custom-hero {
  text-align: center;
  padding: 4rem 1rem;
  background: linear-gradient(135deg, rgba(97, 161, 101, 0.08) 0%, rgba(77, 162, 82, 0.03) 100%);
  border-radius: 16px;
  margin-top: 1rem;
  margin-bottom: 3.5rem;
  border: 1px solid rgba(97, 161, 101, 0.15);
  box-shadow: 0 4px 20px rgba(97, 161, 101, 0.03);
}
.custom-hero h1 {
  font-size: 2.8rem !important;
  font-weight: 800 !important;
  color: #49814D !important;
  margin-bottom: 1rem !important;
  border-bottom: none !important;
  display: block !important; 
}
.custom-hero p {
  font-size: 1.2rem;
  color: #555;
  max-width: 100%; 
  margin: 0 auto 2rem;
  line-height: 1.6;
  white-space: nowrap; /* PC端保持一行 */
}

/* 按钮组 Flex 布局 */
.hero-buttons {
  display: flex;
  justify-content: center;
  align-items: center;
  gap: 1rem;
}
.custom-hero .md-button {
  border-radius: 8px;
  font-weight: 600;
  padding: 0.6rem 1.8rem;
  transition: all 0.3s ease;
  margin: 0 !important;
}

/* 3. 适配暗黑模式的巨幕 */
[data-md-color-scheme="slate"] .custom-hero {
  background: linear-gradient(135deg, rgba(97, 161, 101, 0.15) 0%, rgba(30, 40, 32, 0.5) 100%);
  border-color: rgba(97, 161, 101, 0.3);
}
[data-md-color-scheme="slate"] .custom-hero h1 {
  color: #7EBA82 !important;
}
[data-md-color-scheme="slate"] .custom-hero p {
  color: #A3B8A5;
}

/*移动端强制单行 + 按钮并排自适应*/
@media screen and (max-width: 768px) {
  .custom-hero {
    padding: 2.5rem 0.2rem; /* 压榨左右留白，给文字和按钮腾出最大空间 */
  }
  .custom-hero h1 {
    font-size: 2.2rem !important; /* 标题稍微缩减 */
  }
  .custom-hero p {
    white-space: nowrap !important; 
    /* 1. 把保底字号提升到 0.78rem (约 12.5px)，缩放比例拉大到 3.8vw */
    font-size: clamp(0.78rem, 3.8vw, 1.15rem); 
    /* 2. 把字间距进一步收紧，给变大的字体腾出横向空间 */
    letter-spacing: -0.6px; 
    /* 3. 开启横向平滑缩放，防止某些老旧浏览器文字溢出 */
    transform-origin: center;
    padding: 0;
  }
  .hero-buttons {
    flex-direction: row; /* 强制按钮保持左右横排 */
    gap: 0.5rem; /* 缩小按钮间隔 */
  }
  .hero-buttons .md-button {
    width: auto;
    padding: 0.5rem 1rem; /* 缩小按钮内部留白 */
    font-size: 0.85rem; /* 缩小按钮文字 */
  }
}
</style>

<div class="custom-hero">
  <h1>万象拼音</h1>
  <p>重塑 Rime 生态，带来极致的输入体验。</p>
  <div class="hero-buttons">
    <a href="doc/intro/" class="md-button md-button--primary">🚀 快速上手</a>
    <a href="https://github.com/amzxyz/rime-wanxiang" class="md-button">⭐ GitHub 仓库</a>
  </div>
</div>

## 🧭 探索万象

<div class="grid cards symmetric-2x2" markdown>

-   :material-rocket-launch: __快速上手__
    ---
    从零开始，为您在 Windows、macOS 以及 iOS/Android 移动端部署万象。
    [:octicons-arrow-right-24: 立即安装](doc/intro.md)

-   :material-keyboard-variant: __核心输入体系__
    ---
    深入解析万象独特的“带调拼音标注”、强大的辅码系统（小鹤、自然码等）以及中英混输机制。
    [:octicons-arrow-right-24: 了解核心](doc/aux_code.md)

-   :material-magic-staff: __Lua 魔法扩展__
    ---
    计算器、超级注释、符号包裹、动态时间戳... 探索让 Rime 拥有“超能力”的数十种微创新脚本。
    [:octicons-arrow-right-24: 探索魔法](doc/shijian.md)

-   :material-cogs: __词库与模型__
    ---
    深度解析万象的现代数据工程。算一笔隐形的“时间账”，彻底告别低效的候选翻页，让输入如呼吸般自然。
    [:octicons-arrow-right-24: 揭秘底层逻辑](doc/dict_gram.md)

</div>

---

<div style="margin-top: 2rem;"></div>

## 💎 核心基石：标准版 vs 增强版

万象提供两个主要版本，请根据您的输入习惯选择。为了获得最佳体验，**请务必了解您所选版本的特性**：

| 特性对比 | 🟢 标准版 (Base) | 🔵 增强版 (Pro) |
| :--- | :--- | :--- |
| **适用人群** | 新手、全拼用户、追求省心的双拼用户 | 硬核双拼用户、重度辅码与造词需求者 |
| **方案文件** | `wanxiang.schema.yaml` | `wanxiang_pro.schema.yaml` |
| **支持类型** | 全拼、任意双拼 | **仅支持双拼** |
| **自动调频** | 默认开启 | **默认关闭** (精准控制) |
| **用户词记录** | 自动记录，无差别积累 | 手动/无感造词，词库绝对可控 |
| **辅助码支持** | 仅基于声调的辅助 | **7 种辅助码可选** + 声调辅助 |
| **全场景辅筛** | 支持两分、多分、笔画、声调 | 全面支持 + 专属辅助码筛选 |

---

<div style="margin-top: 2rem;"></div>

## 🤝 参与共建

万象是一个持续打磨的开放生态。我们极度重视数据准确与时效，欢迎您随时反馈。

* 📝 [万象词库问题收集反馈表](https://docs.qq.com/smartsheet/DWHZsdnZZaGh5bWJI?viewId=vUQPXH&tab=BB08J2)
* 🌟 如果觉得项目好用，欢迎在 GitHub 为我们点亮 **Star**！

<div align="center" style="margin-top: 2.5rem;">
    <img src="image/donate.jpg" alt="赞赏支持 AMZ" width="220" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(97, 161, 101, 0.15); border: 1px solid rgba(97, 161, 101, 0.2);">
    <p style="margin-top: 1rem; color: #49814D; font-weight: 600; letter-spacing: 1px;">☕ 感谢您的赞赏与支持</p>
</div>

<br><br>
<div align="center" style="opacity: 0.6; font-size: 0.9em;">
    <i>用更现代的数据，接管你的候选词。</i>
</div>