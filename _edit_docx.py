# -*- coding: utf-8 -*-
"""编辑项目申报书：填写 FEM 超算模拟探究内容，预留模拟结果图片空位"""
import copy, shutil, os
import docx
from docx.oxml import OxmlElement
from docx.oxml.ns import qn

SRC = r'C:\Users\JosephVStalin\Desktop\PysProject\项目申报书模板_原始备份.docx'
TGT = r'C:\Users\JosephVStalin\Desktop\PysProject\项目申报书模板.docx'
shutil.copy2(SRC, TGT)

d = docx.Document(TGT)
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'

def get_rpr(p, idx=0):
    runs = p.findall(qn('w:r'))
    if not runs:
        return None
    r = runs[idx] if idx < len(runs) else runs[0]
    return r.find(qn('w:rPr'))

def remove_bold(rpr):
    if rpr is None:
        return
    for b in rpr.findall(qn('w:b')):
        rpr.remove(b)
    for bcs in rpr.findall(qn('w:bCs')):
        rpr.remove(bcs)

def make_run(text, rpr_tmpl, bold=False, size_half=None, color=None, underline=False):
    r = OxmlElement('w:r')
    rPr = OxmlElement('w:rPr')
    if rpr_tmpl is not None:
        for child in rpr_tmpl:
            rPr.append(copy.deepcopy(child))
    # 去掉可能的 bold / sz / color / u，按需重设
    for tag in ('w:b', 'w:bCs', 'w:sz', 'w:szCs', 'w:color', 'w:u'):
        for el in rPr.findall(qn(tag)):
            rPr.remove(el)
    # 字体确保仿宋
    rf = rPr.find(qn('w:rFonts'))
    if rf is None:
        rf = OxmlElement('w:rFonts')
        rPr.insert(0, rf)
    rf.set(qn('w:ascii'), '仿宋_GB2312')
    rf.set(qn('w:eastAsia'), '仿宋_GB2312')
    rf.set(qn('w:hAnsi'), '仿宋_GB2312')
    if bold:
        b = OxmlElement('w:b'); rPr.append(b)
    if size_half is None:
        size_half = 28  # 默认四号（14pt），与模板正文一致
    sz = OxmlElement('w:sz'); sz.set(qn('w:val'), str(size_half)); rPr.append(sz)
    szc = OxmlElement('w:szCs'); szc.set(qn('w:val'), str(size_half)); rPr.append(szc)
    if color:
        c = OxmlElement('w:color'); c.set(qn('w:val'), color); rPr.append(c)
    if underline:
        u = OxmlElement('w:u'); u.set(qn('w:val'), 'single'); rPr.append(u)
    r.append(rPr)
    t = OxmlElement('w:t'); t.text = text; t.set(qn('xml:space'), 'preserve')
    r.append(t)
    return r

def insert_paras_after(anchor_p_el, texts, rpr_tmpl, bold=False, size_half=None):
    """在 anchor 段落后依次插入多个正文段落，返回最后一个新段落元素"""
    prev = anchor_p_el
    last = None
    for txt in texts:
        p = OxmlElement('w:p')
        pPr = OxmlElement('w:pPr')
        # 复制 anchor 的 pPr（保留 spacing / jc 等）
        src_ppr = anchor_p_el.find(qn('w:pPr'))
        if src_ppr is not None:
            for child in src_ppr:
                pPr.append(copy.deepcopy(child))
        # 移除 pPr 中可能的 outlineLvl / numPr，避免产生编号
        for tag in ('w:numPr', 'w:outlineLvl'):
            for el in pPr.findall(qn(tag)):
                pPr.remove(el)
        p.append(pPr)
        p.append(make_run(txt, rpr_tmpl, bold=bold, size_half=size_half))
        prev.addnext(p)
        prev = p
        last = p
    return last

def make_placeholder_para(caption):
    """创建带边框的图片占位框段落（居中、灰色提示文字）"""
    p = OxmlElement('w:p')
    pPr = OxmlElement('w:pPr')
    pBdr = OxmlElement('w:pBdr')
    for side in ('top', 'left', 'bottom', 'right'):
        el = OxmlElement('w:' + side)
        el.set(qn('w:val'), 'dashed')
        el.set(qn('w:sz'), '8')
        el.set(qn('w:space'), '4')
        el.set(qn('w:color'), '808080')
        pBdr.append(el)
    pPr.append(pBdr)
    spc = OxmlElement('w:spacing')
    spc.set(qn('w:before'), '60')
    spc.set(qn('w:after'), '60')
    pPr.append(spc)
    jc = OxmlElement('w:jc'); jc.set(qn('w:val'), 'center'); pPr.append(jc)
    p.append(pPr)
    rPr_tmpl = None
    p.append(make_run(caption, rPr_tmpl, size_half=24, color='808080'))
    return p

def replace_run_text(p, old, new, must=True):
    """在段落所有 run 中替换文本片段（跨 run 不处理，逐 run 替换）"""
    hit = False
    for r in p.findall(qn('w:r')):
        ts = r.findall(qn('w:t'))
        for t in ts:
            if old in (t.text or ''):
                t.text = t.text.replace(old, new)
                hit = True
    if not hit and must:
        raise RuntimeError(f'未找到要替换的文本: {old!r} in {p}')
    return hit

# ============ 1. 封面 ============
paras = d.paragraphs

# 1.1 项目名称：把"（或作品名称）"替换为实际项目名称（带下划线，仿宋16pt）
p5 = paras[5]._p
runs5 = p5.findall(qn('w:r'))
name = '基于国家超算互联网平台的电磁感应有限元建模与实验探究——以磁体穿过线圈为例'
if len(runs5) >= 4:
    rpr5 = runs5[1].find(qn('w:rPr'))  # "（" run，含下划线
    for r in runs5[1:4]:
        p5.remove(r)
    new_run = make_run(name, rpr5, size_half=32, underline=True)  # 16pt
    p5.append(new_run)

# 1.2 申报类型：勾选"拔尖创新类"
p12 = paras[12]._p
replace_run_text(p12, '□普及类□拔尖创新类', '□普及类☑拔尖创新类')

# 1.3 领域方向：勾选"8.科学与工程创新实践"
p21 = paras[21]._p
replace_run_text(p21, '□', '☑')

# 1.4 修复空白页：把 P25 空段中的分页符内联到"填表时间"段末尾，删除空段
p24 = paras[24]._p  # 填表时间
p25 = paras[25]._p  # 含 <w:br w:type="page"/> 的空段
br = p25.find('.//' + qn('w:br'))
if br is not None:
    r_br = OxmlElement('w:r')
    r_br.append(copy.deepcopy(br))
    p24.append(r_br)
    p25.getparent().remove(p25)

# ============ 2. 表格 ============
t = d.tables[0]

# ---- R1 项目概况 ----
cell1 = t.rows[1].cells[0]
p1_0 = cell1.paragraphs[0]._p   # （1）选题背景提示
p1_1 = cell1.paragraphs[1]._p   # （2）研究核心内容提示
rpr_norm = get_rpr(p1_0)        # 仿宋14pt 非粗体

# 选题背景 + 项目意义（插入到 P1_0 之后）
bg_texts = [
    '选题背景：磁体穿过线圈产生感应电动势，是电磁感应与楞次定律的经典现象，也是中学物理的核心内容。传统探究以定性实验观察为主，难以定量揭示磁场分布与感应电动势的时空变化规律。有限元分析（FEM）是现代应用最广泛的数值模拟方法之一，可在实验之前对磁场、磁链与感应电动势进行三维定量预测；国家超算互联网平台（scnet.cn）提供普惠化高性能算力，使青少年也有机会完成大规模三维有限元求解。本项目将有限元模拟引入电磁感应探究，在标准实验流程之前先进行超算模拟，形成“先模拟、后实验”的探究模式。',
    '项目意义：一是理论意义，通过真实工程软件理解“场”的数值求解思想，把抽象电磁理论转化为可视化的场分布与波形；二是实践价值，以模拟指导实验设计与参数选择，减少盲目试错，提高探究效率；三是能力培养价值，锻炼几何建模、网格划分、并行计算与数据分析能力，培养建模思维与计算思维。',
]
insert_paras_after(p1_0, bg_texts, rpr_norm)

# 研究核心内容 + 图片占位（插入到 P1_1 之后）
core_texts = [
    '核心思路：在“磁体穿过线圈＋示波器观测”标准实验流程之前加入有限元模拟环节，形成“有限元模拟→实验验证→对比分析→迭代优化”的完整探究流程。',
    '①几何建模与网格划分：使用 Gmsh 建立磁体（N52 钕铁硼永磁体，半径 15 mm、高 30 mm）、线圈（内径 20 mm、外径 25 mm、高 40 mm、50 匝）与空气域的三维几何模型，生成约 16 万节点的四面体网格；',
    '②有限元模拟：基于国家超算互联网平台（scnet.cn）的高性能计算资源，使用 Elmer 求解器（Whitney 棱边元法）完成 150 个时间步的三维静磁瞬态求解，输出磁通密度分布、磁链、感应电动势与感应电流波形；',
    '③实验验证：按标准流程搭建磁体穿过线圈实验装置，用示波器采集感应电动势波形，并设置空线圈、铜线闭路、铝线闭路、铝线开路四组对照实验；',
    '④对比分析：将有限元模拟结果与实验数据定量对比，验证模型精度，分析楞次制动等物理机制，并对模型进行迭代优化。',
]
last_core = insert_paras_after(p1_1, core_texts, rpr_norm)

# 图片占位框（3 个）
for cap in [
    '【图1 预留：有限元几何模型与网格划分图（此处插入 FEM 模拟结果图片）】',
    '【图2 预留：有限元模拟结果图（磁通密度云图 / 感应电动势波形）】',
    '【图3 预留：有限元模拟结果与实验数据对比图】',
]:
    ph = make_placeholder_para(cap)
    last_core.addnext(ph)
    last_core = ph

# ---- R2 创新点与特色 ----
cell2 = t.rows[2].cells[0]
p2_0 = cell2.paragraphs[0]._p
rpr2 = get_rpr(p2_0)
innov = [
    '①流程创新：在常规“先实验后分析”的探究流程之前引入有限元模拟，形成“模拟—实验—对比”双轨验证的探究范式；',
    '②方法创新：借助国家超算互联网平台的超算算力完成大规模三维静磁有限元求解，将超级计算与青少年科学探究有机结合。',
]
insert_paras_after(p2_0, innov, rpr2)

# ---- R3 预期效果与价值 ----
cell3 = t.rows[3].cells[0]
p3_0 = cell3.paragraphs[0]._p
rpr3 = get_rpr(p3_0)
effect = [
    '①完成磁体穿过线圈全过程的有限元模拟，获得与解析解高度一致（穿越时间误差＜1%）的磁通密度、感应电动势与感应电流波形；',
    '②完成空线圈、铜线闭路、铝线闭路、铝线开路四组对照实验，实现模拟结果与实验数据的定量对比；',
    '③形成仿真模型、研究数据、研究报告、探究日志与过程视频等成果；',
    '④验证“先模拟、后实验”探究流程的科学性与可行性，为青少年利用超算平台开展科学探究提供可复制的范例。',
]
insert_paras_after(p3_0, effect, rpr3)

# ---- R4 成果形式勾选 ----
cell4 = t.rows[4].cells[0]
ps4 = [p._p for p in cell4.paragraphs]
replace_run_text(ps4[1], '□科学日志', '☑科学日志')
replace_run_text(ps4[2], '□工程日志□研究数据□研究报告', '☑工程日志☑研究数据☑研究报告')
replace_run_text(ps4[3], '□过程视频', '☑过程视频')
replace_run_text(ps4[4], '□仿真模型', '☑仿真模型')

# ---- R5 团队成员分工 ----
cell5 = t.rows[5].cells[0]
p5_0 = cell5.paragraphs[0]._p
rpr5 = get_rpr(p5_0)
div = [
    '①建模计算组：负责三维几何建模、网格划分与有限元求解，包括超算平台作业的提交、监控与结果下载；',
    '②实验组：负责搭建磁体—线圈实验装置，使用示波器采集感应电动势数据；',
    '③数据分析组：负责整理模拟与实验数据，进行波形对比、误差分析与结论提炼；',
    '④展示记录组：负责探究日志、研究数据与过程视频的记录整理，撰写研究报告与项目展板。',
]
insert_paras_after(p5_0, div, rpr5)

# ---- R6 指导教师职责 ----
cell6 = t.rows[6].cells[0]
p6_0 = cell6.paragraphs[0]._p
rpr6 = get_rpr(p6_0)
duty = [
    '①选题与理论指导：指导电磁感应原理、楞次定律及有限元方法入门；',
    '②平台与软件指导：指导超算平台账号申请、作业提交，以及建模、求解与可视化软件的操作；',
    '③实验安全与伦理把关：确保实验操作安全合规，坚持由学生自主完成核心工作，指导教师不替代学生完成关键环节。',
]
insert_paras_after(p6_0, duty, rpr6)

# ---- R7 实施时间：保留空白占位（起___年___月___日；止___年___月___日），不填具体日期 ----

d.save(TGT)
print('SAVED:', TGT, os.path.getsize(TGT))
