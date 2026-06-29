# 💬 超级注释 & Preedit：超越传统的动态提示中枢

> **抛弃僵化的正则转写与粗暴的 OpenCC 全局覆盖。万象从战略架构高度，用 Lua 引擎接管了输入法的“显示大脑”。**

在传统的 Rime 方案中，给候选词加注释（如辅助码）往往通过 `comment_format` 正则写死，或者依赖 OpenCC 替换。这导致了致命缺陷：一旦叠加双拼和声调，正则就无法逆向还原编码；而 OpenCC 又会霸道地清空所有原本的提示信息（如错音提示）。

万象的 **超级注释 (Super Comment)** 与 **超级 Preedit** 插件通过 Lua 实现了多场景、动态化、高优先级区分的智能提示体系。

---

## ⚡ 核心能力与快捷键交互

万象为你预设了三组极其顺手的快捷键，让你在打字过程中可以瞬间通过“三态循环”切换显示效果：

!!! tip "动态状态切换 (快捷键操作)"
    * **`Control + a` (注释开关)**：在【开启辅助码提示】 ➔ 【开启全拼+声调提示】 ➔ 【关闭注释】三个状态间无缝循环（对应 `fuzhu_hint`）。
    * **`Control + s` (编码显示切换)**：在输入编码的位置实时转换为带声调全拼或原码（对应 `tone_display`）。
    * **`Control + c` (拆分透视)**：强行开启汉字的“拆分辅助提示”。它的优先级最高，能直接覆盖普通提示，帮你在打字中学习（对应 `chaifen_switch`）。

<div style="display: flex; flex-direction: column; gap: 30px; align-items: center; margin: 2rem auto;">
    <div style="text-align: center; width: 100%; max-width: 600px;">
        <img src="https://storage.deepin.org/thread/202509260134283927_辅助码提示.jpg" 
             style="width: 100%; height: auto; border-radius: 10px; box-shadow: 0 6px 16px rgba(0,0,0,0.12);">
        <p style="font-size: 0.95em; color: #666; margin-top: 0.8rem;">Ctrl+a 循环切换：辅助码提示</p>
    </div>
    
    <div style="text-align: center; width: 100%; max-width: 600px;">
        <img src="https://storage.deepin.org/thread/202509260134278003_声调提示.jpg" 
             style="width: 100%; height: auto; border-radius: 10px; box-shadow: 0 6px 16px rgba(0,0,0,0.12);">
        <p style="font-size: 0.95em; color: #666; margin-top: 0.8rem;">Ctrl+a 循环切换：声调全拼提示</p>
    </div>
    
    <div style="text-align: center; width: 100%; max-width: 600px;">
        <img src="https://storage.deepin.org/thread/202509260134284782_拆分提示.jpg" 
             style="width: 100%; height: auto; border-radius: 10px; box-shadow: 0 6px 16px rgba(0,0,0,0.12);">
        <p style="font-size: 0.95em; color: #666; margin-top: 0.8rem;">Ctrl+c 最高优先级：拆分透视提示</p>
    </div>
</div>

---

## 🔬 架构优势：为什么万象更强大？

!!! bug "传统 Rime 方案的痛点"
    * **正则转换限制**：一旦叠加辅助码，传统 `comment_format` 无法做逆向无规则编码的工程转换。
    
    * **OpenCC 覆盖**：OpenCC 启用时会执行全局覆盖，直接清空原本所有的有用注释。

**万象的降维打击：原生带调词库与反查滤镜**

我们不仅抛弃了霸道的 OpenCC，通过 **`reverse_lookup` (反查滤镜)** 将庞大的数据编译为 Rime 最完美的 `.bin` 键值对格式；更做了一项颠覆性的底层重构——**将“声调基因”直接刻入了海量词库的血脉之中！**

传统方案在编码区（Preedit）的提示，全靠外挂的正则表达式死板地去“猜”。而万象由于词库**自带精确编码**，做到了绝对的技术碾压：不管你敲击的是什么天马行空的双拼按键，打出的是多复杂的词组甚至整句，系统都能通过底层数据，将**原汁原味、绝对精准的带调全拼**，瞬间逆向投射回你的编码区！

!!! success "绝无仅有的多音字克星"
    正因为这种“词库原生带调”的底层逻辑，万象成为了**目前唯一一个能真正在编码区 100% 正确显示多音字读音的方案，没有之一！** 
    
    输入“银行（háng）”还是“行为（xíng）”，编码区实时精准注音，绝不含糊。绝不会出现OpenCC银行（xíng，háng）这种莫名无效提示！

得益于这种自带原生数据的词库，结合强大的 Lua 引擎进行内部逻辑调度，万象实现了前所未有的体验升华：

1. **超级 Preedit 的绝对还原**：无论你的双拼方案如何映射（哪怕 zh/ch/sh 藏得再深），Lua 都能直接从第一候选词中提取最真实的“带调全拼”并在编码区完美重现。你甚至可以直接按下 `Shift + Enter`，将这段标有精确声调的拼音作为文本直接上屏！

2. **多场景动态化分发**：错音立马纠正提示（如打 `gei yu` 提示 `jǐ yǔ`）、反查立马显示结构、平时则安静地显示辅助码。所有信息各司其职，优先级自动统筹，绝不互相踩踏。

3. **即时无感开关**：如此强大的全局提示能力，完全不抢占宝贵的候选词位置。通过快捷键随时随地一键启停，收放自如。

---

## ⚙️ 引擎解密：状态机 (Switches) 与快捷键

在万象的底层配置中，控制这些显示的核心是两组互斥的 **Options** 状态机。

### 1. 状态机原版配置
这两组开关分别归属于 `preedit` 和 `comment` 的状态处理：

```yaml
# 1. 编码区 (Preedit) 显示状态组
# 影响输入码位置的实时转换（如显示带声调全拼）
- options: [raw_input, tone_display, full_pinyin]
  states: [原编码, 有声调, 无声调]

# 2. 注释区 (Comment) 显示状态组
# 影响候选词后的提示信息（如辅助码或读音）
- options: [comment_off, fuzhu_hint, tone_hint]
  states: [注释关, 辅助开, 读音开]
```

### 2. 快捷键底层映射
通过 `key_binder` 实现与上述状态的联动：

```yaml
key_binder:
  bindings:
    # Control+c：拆分提示开关
    - {when: has_menu, accept: "Control+c", toggle: chaifen_switch}
    # Control+a：辅助码/读音提示循环
    - {when: has_menu, accept: "Control+a", toggle: fuzhu_hint}
    # Control+s：编码区声调显示开关
    - {when: has_menu, accept: "Control+s", toggle: tone_display}
```

---

## 🛠️ 进阶：如何永久固化一种状态 (Reset)？

如果你希望默认开启辅助码显示，不想每次都按快捷键，可以通过 Patch 修改 `reset` 初始值：

!!! note "利用 Reset 固化状态的 Patch 示例"
    将以下代码加入你的 `wanxiang.custom.yaml`：
    pro和base顺序不一样，请按实际数组从0数

    ```yaml 
    patch:
      # 固定开启：编码区域显示读音
      switches/@9/reset: 1
      
      # 固定开启：注释区域显示读音
      switches/@10/reset: 2

    ```

### 更多自定义项 (Patch)：
```yaml
patch:
  "super_comment/candidate_length": 2            # 词组辅助码提醒的生效长度
  "super_comment/corrector_type": "〔comment〕"    # 随意更换注释括号样式
  "super_comment/cand_type/user_phrase": " ⁺"    # 用户造词外显标记
  "super_comment/cand_type/sentence": " ∞"       # 动态句子外显标记
```

---
<div align="center" style="opacity: 0.5; font-size: 0.85em; margin-top: 2rem;">
    万象超级注释：打破规则，重塑显示的艺术。
</div>