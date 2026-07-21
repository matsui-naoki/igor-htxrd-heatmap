#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3
#pragma IgorVersion=8
#pragma version=1.0

// ============================================================================
//  HT_XRD_Viewer.ipf
//  高温放射光XRD (BL02B2 sweep) ビューア + CIF理論XRD計算
//
//  機能:
//   1. sweep .dat フォルダ一括読込 (ファイル名 sv###K から温度を取得)
//   2. Heatmap: 横軸 2theta / 縦軸 温度(K) / 強度カラー  (図サイズcm固定, Arial)
//   3. CIF (最大3個) から理論XRDパターン計算 (波長/FWHM/eta/範囲/分解能 指定可)
//   4. Heatmap + 理論パターンを同一2theta軸で縦に並べた合成図
//
//  使い方: メニュー "HT-XRD" → "Open Panel"
//  検証: 原子散乱因子・強度式は pymatgen XRDCalculator と同一
// ============================================================================

Menu "HT-XRD"
	"Open Panel", /Q, HTXRD_OpenPanel()
End

// ---------------------------------------------------------------- constants
static Constant kCM2PT = 28.3465			// 1 cm in points

// ============================================================================
//  Initialization
// ============================================================================

static Function EnsureVar(name, val)
	String name
	Variable val
	NVAR/Z v = $("root:HTXRD:" + name)
	if(!NVAR_Exists(v))
		Variable/G $("root:HTXRD:" + name) = val
	endif
End

static Function EnsureStr(name, val)
	String name, val
	SVAR/Z s = $("root:HTXRD:" + name)
	if(!SVAR_Exists(s))
		String/G $("root:HTXRD:" + name) = val
	endif
End

Function HTXRD_Init()
	if(!DataFolderExists("root:HTXRD"))
		NewDataFolder root:HTXRD
	endif
	// --- figure settings
	EnsureVar("gFigW", 8.5)			// figure width (cm) -- journal single column
	EnsureVar("gHeatH", 6.0)			// heatmap height (cm)
	EnsureVar("gFont", 12)			// global font size (pt)
	EnsureVar("gTthMin", 1)
	EnsureVar("gTthMax", 41)
	EnsureVar("gTMin", 300)
	EnsureVar("gTMax", 950)
	EnsureVar("gLog", 0)				// log10 intensity
	EnsureVar("gCbar", 1)			// show color bar
	EnsureVar("gZauto", 1)			// autoscale color
	EnsureVar("gZmin", 0)
	EnsureVar("gZmax", 10000)
	EnsureStr("gCtab", "YellowHot")
	// --- CIF calculation settings
	EnsureVar("gLam", 0.5)			// wavelength (A)
	EnsureVar("gCmin", 1)			// calc 2theta min
	EnsureVar("gCmax", 41)			// calc 2theta max
	EnsureVar("gCstep", 0.01)		// calc 2theta step
	EnsureVar("gFWHM", 0.05)			// peak FWHM (deg)
	EnsureVar("gEta", 0.6)			// pseudo-Voigt eta (0=Gauss, 1=Lorentz)
	EnsureVar("gCIFh", 6.0)			// CIF figure height (cm) -- free
	EnsureVar("gPkSlot", 1)
	// --- combined figure
	EnsureVar("gFrac", 0.35)			// fraction of height used by CIF panel
	EnsureVar("gCombH", 12.0)		// combined figure total height (cm)
	// --- state
	EnsureVar("gCIFload0", 0)
	EnsureVar("gCIFload1", 0)
	EnsureVar("gCIFload2", 0)
	EnsureStr("gDataInfo", "(no data loaded)")
	EnsureStr("gCIFn0", "(empty)")
	EnsureStr("gCIFn1", "(empty)")
	EnsureStr("gCIFn2", "(empty)")
	HTXRD_BuildScattTable()
End

// ============================================================================
//  Atomic scattering factors  (same coefficients & formula as pymatgen:
//  f = Z - 41.78214 * s^2 * sum_i( a_i * exp(-b_i * s^2) ),  s = sin(theta)/lambda )
// ============================================================================

Function HTXRD_BuildScattTable()
	String sc = ""
	sc += "D,1,0.202,30.868,0.244,8.544,0.082,1.273,0,0;H,1,0.202,30.868,0.244,8.544,0.082,1.273,0,0;He,2,0.091,18.183,0.181,6.212,0.11,1.803,0.036,0.284;"
	sc += "Li,3,1.611,107.638,1.246,30.48,0.326,4.533,0.099,0.495;Be,4,1.25,60.804,1.334,18.591,0.36,3.653,0.106,0.416;"
	sc += "B,5,0.945,46.444,1.312,14.178,0.419,3.223,0.116,0.377;C,6,0.731,36.995,1.195,11.297,0.456,2.814,0.125,0.346;N,7,0.572,28.847,1.043,9.054,0.465,2.421,0.131,0.317;"
	sc += "O,8,0.455,23.78,0.917,7.622,0.472,2.144,0.138,0.296;F,9,0.387,20.239,0.811,6.609,0.475,1.931,0.146,0.279;Ne,10,0.303,17.64,0.72,5.86,0.475,1.762,0.153,0.266;"
	sc += "Na,11,2.241,108.004,1.333,24.505,0.907,3.391,0.286,0.435;Mg,12,2.268,73.67,1.803,20.175,0.839,3.013,0.289,0.405;"
	sc += "Al,13,2.276,72.322,2.428,19.773,0.858,3.08,0.317,0.408;Si,14,2.129,57.775,2.533,16.476,0.835,2.88,0.322,0.386;"
	sc += "P,15,1.888,44.876,2.469,13.538,0.805,2.642,0.32,0.361;S,16,1.659,36.65,2.386,11.488,0.79,2.469,0.321,0.34;Cl,17,1.452,30.935,2.292,9.98,0.787,2.234,0.322,0.323;"
	sc += "Ar,18,1.274,26.682,2.19,8.813,0.793,2.219,0.326,0.307;K,19,3.951,137.075,2.545,22.402,1.98,4.532,0.482,0.434;"
	sc += "Ca,20,4.47,99.523,2.971,22.696,1.97,4.195,0.482,0.417;Sc,21,3.966,88.96,2.917,20.606,1.925,3.856,0.48,0.399;"
	sc += "Ti,22,3.565,81.982,2.818,19.049,1.893,3.59,0.483,0.386;V,23,3.245,76.379,2.698,17.726,1.86,3.363,0.486,0.374;"
	sc += "Cr,24,2.307,78.405,2.334,15.785,1.823,3.157,0.49,0.364;Mn,25,2.747,67.786,2.456,15.674,1.792,3,0.498,0.357;Fe,26,2.544,64.424,2.343,14.88,1.759,2.854,0.506,0.35;"
	sc += "Co,27,2.367,61.431,2.236,14.18,1.724,2.725,0.515,0.344;Ni,28,2.21,58.727,2.134,13.553,1.689,2.609,0.524,0.339;"
	sc += "Cu,29,1.579,62.94,1.82,12.453,1.658,2.504,0.532,0.333;Zn,30,1.942,54.162,1.95,12.518,1.619,2.416,0.543,0.33;"
	sc += "Ga,31,2.321,65.602,2.486,15.458,1.688,2.581,0.599,0.351;Ge,32,2.447,55.893,2.702,14.393,1.616,2.446,0.601,0.342;"
	sc += "As,33,2.399,45.718,2.79,12.817,1.529,2.28,0.594,0.328;Se,34,2.298,38.83,2.854,11.536,1.456,2.146,0.59,0.316;"
	sc += "Br,35,2.166,33.899,2.904,10.497,1.395,2.041,0.589,0.307;Kr,36,2.034,29.999,2.927,9.598,1.342,1.952,0.589,0.299;"
	sc += "Rb,37,4.776,140.782,3.859,18.991,2.234,3.701,0.868,0.419;Sr,38,5.848,104.972,4.003,19.367,2.342,3.737,0.88,0.414;Y,39,4.129,27.548,3.012,5.088,1.179,0.591,0,0;"
	sc += "Zr,40,4.105,28.492,3.144,5.277,1.229,0.601,0,0;Nb,41,4.237,27.415,3.105,5.074,1.234,0.593,0,0;Mo,42,3.12,72.464,3.906,14.642,2.361,3.237,0.85,0.366;"
	sc += "Tc,43,4.318,28.246,3.27,5.148,1.287,0.59,0,0;Ru,44,4.358,27.881,3.298,5.179,1.323,0.594,0,0;Rh,45,4.431,27.911,3.343,5.153,1.345,0.592,0,0;"
	sc += "Pd,46,4.436,28.67,3.454,5.269,1.383,0.595,0,0;Ag,47,2.036,61.497,3.272,11.824,2.511,2.846,0.837,0.327;Cd,48,2.574,55.675,3.259,11.838,2.547,2.784,0.838,0.322;"
	sc += "In,49,3.153,66.649,3.557,14.449,2.818,2.976,0.884,0.335;Sn,50,3.45,59.104,3.735,14.179,2.118,2.855,0.877,0.327;"
	sc += "Sb,51,3.564,50.487,3.844,13.316,2.687,2.691,0.864,0.316;Te,52,4.785,27.999,3.688,5.083,1.5,0.581,0,0;I,53,3.473,39.441,4.06,11.816,2.522,2.415,0.84,0.298;"
	sc += "Xe,54,3.366,35.509,4.147,11.117,2.443,2.294,0.829,0.289;Cs,55,6.062,155.837,5.986,19.695,3.303,3.335,1.096,0.379;"
	sc += "Ba,56,7.821,117.657,6.004,18.778,3.28,3.263,1.103,0.376;La,57,4.94,28.716,3.968,5.245,1.663,0.594,0,0;Ce,58,5.007,28.283,3.98,5.183,1.678,0.589,0,0;"
	sc += "Pr,59,5.085,28.588,4.043,5.143,1.684,0.581,0,0;Nd,60,5.151,28.304,4.075,5.073,1.683,0.571,0,0;Pm,61,5.201,28.079,4.094,5.081,1.719,0.576,0,0;"
	sc += "Sm,62,5.255,28.016,4.113,5.037,1.743,0.577,0,0;Eu,63,6.267,100.298,4.844,16.066,3.202,2.98,1.2,0.367;Gd,64,5.225,29.158,4.314,5.259,1.827,0.586,0,0;"
	sc += "Tb,65,5.272,29.046,4.347,5.226,1.844,0.585,0,0;Dy,66,5.332,28.888,4.37,5.198,1.863,0.581,0,0;Ho,67,5.376,28.773,4.403,5.174,1.884,0.582,0,0;"
	sc += "Er,68,5.436,28.655,4.437,5.117,1.891,0.577,0,0;Tm,69,5.441,29.149,4.51,5.264,1.956,0.59,0,0;Yb,70,5.529,28.927,4.533,5.144,1.945,0.578,0,0;"
	sc += "Lu,71,5.553,28.907,4.58,5.16,1.969,0.577,0,0;Hf,72,5.588,29.001,4.619,5.164,1.997,0.579,0,0;Ta,73,5.659,28.807,4.63,5.114,2.014,0.578,0,0;"
	sc += "W,74,5.709,28.782,4.677,5.084,2.019,0.572,0,0;Re,75,5.695,28.968,4.74,5.156,2.064,0.575,0,0;Os,76,5.75,28.933,4.773,5.139,2.079,0.573,0,0;"
	sc += "Ir,77,5.754,29.159,4.851,5.152,2.096,0.57,0,0;Pt,78,5.803,29.016,4.87,5.15,2.127,0.572,0,0;Au,79,2.388,42.866,4.226,9.743,2.689,2.264,1.255,0.307;"
	sc += "Hg,80,2.682,42.822,4.241,9.856,2.755,2.295,1.27,0.307;Tl,81,5.932,29.086,4.972,5.126,2.195,0.572,0,0;Pb,82,3.51,52.914,4.552,11.884,3.154,2.571,1.359,0.321;"
	sc += "Bi,83,3.841,50.261,4.679,11.999,3.192,2.56,1.363,0.318;Po,84,6.07,28.075,4.997,4.999,2.232,0.563,0,0;At,85,6.133,28.047,5.031,4.957,2.239,0.558,0,0;"
	sc += "Rn,86,4.078,38.406,4.978,11.02,3.096,2.355,1.326,0.299;Fr,87,6.201,28.2,5.121,4.954,2.275,0.556,0,0;Ra,88,6.215,28.382,5.17,5.002,2.316,0.562,0,0;"
	sc += "Ac,89,6.278,28.323,5.195,4.949,2.321,0.557,0,0;Th,90,6.264,28.651,5.263,5.03,2.367,0.563,0,0;Pa,91,6.306,28.688,5.303,5.026,2.386,0.561,0,0;"
	sc += "U,92,6.767,85.951,6.729,15.642,4.014,2.936,1.561,0.335;Np,93,6.323,29.142,5.414,5.096,2.453,0.568,0,0;Pu,94,6.415,28.836,5.419,5.022,2.449,0.561,0,0;"
	sc += "Am,95,6.378,29.156,5.495,5.102,2.495,0.565,0,0;Cm,96,6.46,28.396,5.469,4.97,2.471,0.554,0,0;Bk,97,6.502,28.375,5.478,4.975,2.51,0.561,0,0;"
	sc += "Cf,98,6.548,28.461,5.526,4.965,2.52,0.557,0,0;"
	Variable n = ItemsInList(sc, ";")
	Make/O/T/N=(n) root:HTXRD:scElem
	Make/O/N=(n) root:HTXRD:scZ
	Make/O/N=(n, 8) root:HTXRD:scAB
	Wave/T scElem = root:HTXRD:scElem
	Wave scZ = root:HTXRD:scZ
	Wave scAB = root:HTXRD:scAB
	Variable i, j
	String rec
	for(i = 0; i < n; i += 1)
		rec = StringFromList(i, sc, ";")
		scElem[i] = StringFromList(0, rec, ",")
		scZ[i] = str2num(StringFromList(1, rec, ","))
		for(j = 0; j < 8; j += 1)
			scAB[i][j] = str2num(StringFromList(2 + j, rec, ","))
		endfor
	endfor
End

static Function HTXRD_ElemIdx(sym)
	String sym
	Wave/T scElem = root:HTXRD:scElem
	Variable i, n = numpnts(scElem)
	for(i = 0; i < n; i += 1)
		if(CmpStr(scElem[i], sym, 1) == 0)
			return i
		endif
	endfor
	return -1
End

// "Ba2+", "Li0", "S2-", "F" などから元素記号を抽出
static Function/S HTXRD_ElemFromStr(s)
	String s
	String out = ""
	Variable i, cc, n = strlen(s)
	for(i = 0; i < n; i += 1)
		cc = char2num(s[i, i])
		if((cc >= 65 && cc <= 90) || (cc >= 97 && cc <= 122))
			out += s[i, i]
			if(strlen(out) == 2)
				break
			endif
		else
			if(strlen(out) > 0)
				break
			endif
		endif
	endfor
	// 2文字目が実在しない元素の場合は 1 文字に落とす ("PB"→"Pb"は無い前提, CIFは正書式)
	if(strlen(out) == 2 && HTXRD_ElemIdx(out) < 0)
		out = out[0, 0]
	endif
	return out
End

// ============================================================================
//  Panel
// ============================================================================

Function HTXRD_OpenPanel()
	HTXRD_Init()
	DoWindow/K HTXRD_Panel
	NewPanel/K=1/N=HTXRD_Panel/W=(80, 60, 490, 750) as "HT-XRD Viewer"
	ModifyPanel/W=HTXRD_Panel fixedSize=1
	Variable y

	// ---- 1. data ----
	GroupBox grpData, pos={8, 6}, size={394, 84}, title="1. Sweep data (.dat folder)", fSize=12
	Button btnLoadSweep, pos={20, 26}, size={170, 26}, proc=HTXRD_BtnProc, title="Load sweep folder..."
	SetVariable svInfo, pos={20, 60}, size={370, 18}, value=root:HTXRD:gDataInfo, noedit=1, frame=0, title=" "

	// ---- 2. heatmap ----
	y = 96
	GroupBox grpFig, pos={8, y}, size={394, 176}, title="2. Heatmap (x: 2θ, y: T)", fSize=12
	SetVariable svW, pos={20, y+22}, size={118, 18}, value=root:HTXRD:gFigW, limits={3, 30, 0.5}, title="Width(cm)"
	SetVariable svH, pos={146, y+22}, size={118, 18}, value=root:HTXRD:gHeatH, limits={2, 30, 0.5}, title="Height(cm)"
	SetVariable svFont, pos={272, y+22}, size={118, 18}, value=root:HTXRD:gFont, limits={6, 24, 1}, title="Font(pt)"
	SetVariable svXmin, pos={20, y+46}, size={118, 18}, value=root:HTXRD:gTthMin, limits={0, 90, 1}, title="2θ min"
	SetVariable svXmax, pos={146, y+46}, size={118, 18}, value=root:HTXRD:gTthMax, limits={0, 90, 1}, title="2θ max"
	SetVariable svTmin, pos={20, y+70}, size={118, 18}, value=root:HTXRD:gTMin, limits={0, 3000, 10}, title="T min(K)"
	SetVariable svTmax, pos={146, y+70}, size={118, 18}, value=root:HTXRD:gTMax, limits={0, 3000, 10}, title="T max(K)"
	PopupMenu popCtab, pos={272, y+68}, size={118, 19}, proc=HTXRD_PopProc, title="Color"
	PopupMenu popCtab, mode=3, popvalue="YellowHot", value="Turbo;Rainbow;YellowHot;Grays;ColdWarm;SpectrumBlack"
	CheckBox chkLog, pos={20, y+96}, size={90, 15}, variable=root:HTXRD:gLog, title="log10 intensity"
	CheckBox chkCbar, pos={146, y+96}, size={90, 15}, variable=root:HTXRD:gCbar, title="color bar"
	CheckBox chkZauto, pos={272, y+96}, size={90, 15}, variable=root:HTXRD:gZauto, title="auto z-scale"
	SetVariable svZmin, pos={20, y+118}, size={140, 18}, value=root:HTXRD:gZmin, title="z min"
	SetVariable svZmax, pos={168, y+118}, size={140, 18}, value=root:HTXRD:gZmax, title="z max"
	Button btnHeat, pos={20, y+142}, size={190, 26}, proc=HTXRD_BtnProc, title="Make heatmap", fStyle=1

	// ---- 3. CIF ----
	y = 280
	GroupBox grpCIF, pos={8, y}, size={394, 266}, title="3. Calculated XRD from CIF", fSize=12
	SetVariable svLam, pos={20, y+22}, size={130, 18}, value=root:HTXRD:gLam, limits={0.1, 3, 0.01}, title="λ (Å)"
	SetVariable svFWHM, pos={158, y+22}, size={112, 18}, value=root:HTXRD:gFWHM, limits={0.001, 2, 0.01}, title="FWHM(°)"
	SetVariable svEta, pos={278, y+22}, size={112, 18}, value=root:HTXRD:gEta, limits={0, 1, 0.1}, title="η (PV)"
	SetVariable svCmin, pos={20, y+46}, size={112, 18}, value=root:HTXRD:gCmin, limits={0.1, 90, 1}, title="2θ min"
	SetVariable svCmax, pos={140, y+46}, size={112, 18}, value=root:HTXRD:gCmax, limits={0.1, 90, 1}, title="2θ max"
	SetVariable svCstep, pos={260, y+46}, size={130, 18}, value=root:HTXRD:gCstep, limits={0.001, 0.5, 0.005}, title="step(°)"
	Button btnCIF0, pos={20, y+72}, size={110, 24}, proc=HTXRD_BtnProc, title="Load CIF 1..."
	SetVariable svCn0, pos={140, y+76}, size={250, 18}, value=root:HTXRD:gCIFn0, noedit=1, frame=0, title=" "
	Button btnCIF1, pos={20, y+102}, size={110, 24}, proc=HTXRD_BtnProc, title="Load CIF 2..."
	SetVariable svCn1, pos={140, y+106}, size={250, 18}, value=root:HTXRD:gCIFn1, noedit=1, frame=0, title=" "
	Button btnCIF2, pos={20, y+132}, size={110, 24}, proc=HTXRD_BtnProc, title="Load CIF 3..."
	SetVariable svCn2, pos={140, y+136}, size={250, 18}, value=root:HTXRD:gCIFn2, noedit=1, frame=0, title=" "
	Button btnClearCIF, pos={20, y+162}, size={110, 22}, proc=HTXRD_BtnProc, title="Clear all CIF"
	SetVariable svCIFh, pos={150, y+164}, size={160, 18}, value=root:HTXRD:gCIFh, limits={2, 30, 0.5}, title="Fig height(cm)"
	Button btnPlotCIF, pos={20, y+192}, size={220, 26}, proc=HTXRD_BtnProc, title="Calculate + plot patterns", fStyle=1
	PopupMenu popPk, pos={20, y+228}, size={100, 19}, proc=HTXRD_PopProc, title="Peak list"
	PopupMenu popPk, mode=1, value="CIF 1;CIF 2;CIF 3"
	Button btnPkTable, pos={140, y+226}, size={130, 22}, proc=HTXRD_BtnProc, title="Show peak table"

	// ---- 4. combined ----
	y = 554
	GroupBox grpComb, pos={8, y}, size={394, 90}, title="4. Combined figure (heatmap + CIF)", fSize=12
	SetVariable svFrac, pos={20, y+24}, size={170, 18}, value=root:HTXRD:gFrac, limits={0.1, 0.8, 0.05}, title="CIF area fraction"
	SetVariable svCombH, pos={200, y+24}, size={180, 18}, value=root:HTXRD:gCombH, limits={4, 40, 0.5}, title="Total height(cm)"
	Button btnComb, pos={20, y+52}, size={220, 26}, proc=HTXRD_BtnProc, title="Make combined figure", fStyle=1

	TitleBox tbCredit, pos={20, 652}, size={300, 15}, frame=0, title="HT-XRD Viewer v1.0  (BL02B2 sweep data)"
End

Function HTXRD_BtnProc(ba) : ButtonControl
	STRUCT WMButtonAction &ba
	if(ba.eventCode != 2)
		return 0
	endif
	NVAR gPkSlot = root:HTXRD:gPkSlot
	strswitch(ba.ctrlName)
		case "btnLoadSweep":
			HTXRD_LoadSweep()
			break
		case "btnHeat":
			HTXRD_MakeHeatmap()
			break
		case "btnCIF0":
			HTXRD_LoadCIF(0)
			break
		case "btnCIF1":
			HTXRD_LoadCIF(1)
			break
		case "btnCIF2":
			HTXRD_LoadCIF(2)
			break
		case "btnClearCIF":
			HTXRD_ClearCIFs()
			break
		case "btnPlotCIF":
			HTXRD_CalcAll()
			HTXRD_PlotCIFs()
			break
		case "btnPkTable":
			HTXRD_ShowPeakTable(gPkSlot - 1)
			break
		case "btnComb":
			HTXRD_MakeCombined()
			break
	endswitch
	return 0
End

Function HTXRD_PopProc(pa) : PopupMenuControl
	STRUCT WMPopupAction &pa
	if(pa.eventCode != 2)
		return 0
	endif
	strswitch(pa.ctrlName)
		case "popCtab":
			SVAR gCtab = root:HTXRD:gCtab
			gCtab = pa.popStr
			break
		case "popPk":
			NVAR gPkSlot = root:HTXRD:gPkSlot
			gPkSlot = pa.popNum
			break
	endswitch
	return 0
End

// ============================================================================
//  1. Sweep data loading
//     ファイル名 ..._sv312.0K_... から温度を取得し, 温度昇順に並べた
//     行列 matRaw (行: 2theta, 列: 温度) を作る
// ============================================================================

static Function HTXRD_TempFromName(fn)
	String fn
	Variable i = strsearch(fn, "_sv", 0)
	if(i < 0)
		return NaN
	endif
	Variable k = strsearch(fn, "K", i)
	if(k < 0)
		return NaN
	endif
	return str2num(fn[i + 3, k - 1])
End

Function HTXRD_LoadSweep()
	HTXRD_Init()
	SVAR gDataInfo = root:HTXRD:gDataInfo
	NVAR gTthMin = root:HTXRD:gTthMin
	NVAR gTthMax = root:HTXRD:gTthMax
	NVAR gTMin = root:HTXRD:gTMin
	NVAR gTMax = root:HTXRD:gTMax

	NewPath/O/Q/M="sweep .dat ファイルのあるフォルダを選択" HTXRDdata
	if(V_flag != 0)
		return -1
	endif
	String files = IndexedFile(HTXRDdata, -1, ".dat")
	Variable nf = ItemsInList(files)
	if(nf == 0)
		DoAlert 0, "フォルダ内に .dat ファイルが見つかりません"
		return -1
	endif

	// 温度が読めるファイルだけ集める
	Make/O/T/N=0 root:HTXRD:okFiles
	Make/O/N=0 root:HTXRD:okTemp
	Wave/T okFiles = root:HTXRD:okFiles
	Wave okTemp = root:HTXRD:okTemp
	Variable i, tt, cnt = 0
	String fn
	for(i = 0; i < nf; i += 1)
		fn = StringFromList(i, files)
		tt = HTXRD_TempFromName(fn)
		if(numtype(tt) == 0)
			cnt += 1
			Redimension/N=(cnt) okFiles, okTemp
			okFiles[cnt - 1] = fn
			okTemp[cnt - 1] = tt
		endif
	endfor
	if(cnt == 0)
		DoAlert 0, "ファイル名から温度 (sv###K) を読み取れませんでした"
		return -1
	endif
	Printf "HTXRD: %d/%d files with sv###K temperature tag\r", cnt, nf

	// 1st file で点数と2thetaグリッドを確定
	LoadWave/Q/G/O/P=HTXRDdata/N=tmpXRD okFiles[0]
	Wave w0 = tmpXRD0
	Wave w1 = tmpXRD1
	Variable npt = numpnts(w0)
	Duplicate/O w0, root:HTXRD:tthW
	Wave tthW = root:HTXRD:tthW
	Variable t0 = tthW[0]
	Variable dt = (tthW[npt - 1] - t0) / (npt - 1)

	// 全ファイル読込
	Make/O/N=(npt, cnt) root:HTXRD:matTmp
	Wave matTmp = root:HTXRD:matTmp
	Variable m
	for(i = 0; i < cnt; i += 1)
		LoadWave/Q/G/O/P=HTXRDdata/N=tmpXRD okFiles[i]
		Wave w1 = tmpXRD1
		m = min(npt, numpnts(w1))
		matTmp[0, m - 1][i] = w1[p]
		if(mod(i, 50) == 0)
			Printf "HTXRD: loading %d / %d\r", i, cnt
		endif
	endfor
	KillWaves/Z tmpXRD0, tmpXRD1

	// 温度昇順に並べ替え
	Make/O/N=(cnt) root:HTXRD:sortIdx
	Wave sortIdx = root:HTXRD:sortIdx
	MakeIndex okTemp, sortIdx
	Make/O/N=(cnt) root:HTXRD:tempSorted
	Wave tempSorted = root:HTXRD:tempSorted
	tempSorted = okTemp[sortIdx[p]]
	// 同一温度の重複は僅かにずらす (image の y エッジ単調性のため)
	for(i = 1; i < cnt; i += 1)
		if(tempSorted[i] <= tempSorted[i - 1])
			tempSorted[i] = tempSorted[i - 1] + 0.01
		endif
	endfor
	Make/O/N=(npt, cnt) root:HTXRD:matRaw
	Wave matRaw = root:HTXRD:matRaw
	matRaw = matTmp[p][sortIdx[q]]
	KillWaves/Z root:HTXRD:matTmp
	SetScale/P x, t0, dt, matRaw

	// 温度エッジ (非等間隔対応)
	Make/O/N=(cnt + 1) root:HTXRD:tempEdges
	Wave tempEdges = root:HTXRD:tempEdges
	if(cnt == 1)
		tempEdges[0] = tempSorted[0] - 0.5
		tempEdges[1] = tempSorted[0] + 0.5
	else
		tempEdges[1, cnt - 1] = (tempSorted[p - 1] + tempSorted[p]) / 2
		tempEdges[0] = tempSorted[0] - (tempSorted[1] - tempSorted[0]) / 2
		tempEdges[cnt] = tempSorted[cnt - 1] + (tempSorted[cnt - 1] - tempSorted[cnt - 2]) / 2
	endif

	// 表示レンジ初期値
	gTthMin = tthW[0]
	gTthMax = tthW[npt - 1]
	gTMin = tempEdges[0]
	gTMax = tempEdges[cnt]
	sprintf fn, "%d files | T = %.1f - %.1f K | 2θ = %.3f - %.3f° (%d pts)", cnt, tempSorted[0], tempSorted[cnt - 1], tthW[0], tthW[npt - 1], npt
	gDataInfo = fn
	Printf "HTXRD: %s\r", fn
	return 0
End

// ============================================================================
//  Graph style helper: Arial + 一括フォントサイズ + publication 体裁
// ============================================================================

static Function HTXRD_ApplyStyle(win)
	String win
	NVAR gFont = root:HTXRD:gFont
	ModifyGraph/W=$win font="Arial", fSize=gFont
	ModifyGraph/W=$win mirror=1, tick=2, btLen=4, stLen=2, standoff=0
	ModifyGraph/W=$win minor=1
	ModifyGraph/W=$win expand=2, axThick=0.5
End

static Function/S HTXRD_TthLabel()
	return "2\\f02θ\\f00 / º"
End

// ============================================================================
//  2. Heatmap
// ============================================================================

Function HTXRD_MakeHeatmap()
	Wave/Z matRaw = root:HTXRD:matRaw
	if(!WaveExists(matRaw))
		DoAlert 0, "先に sweep データを読み込んでください"
		return -1
	endif
	NVAR gFigW = root:HTXRD:gFigW
	NVAR gHeatH = root:HTXRD:gHeatH
	NVAR gLog = root:HTXRD:gLog
	NVAR gCbar = root:HTXRD:gCbar
	NVAR gZauto = root:HTXRD:gZauto
	NVAR gZmin = root:HTXRD:gZmin
	NVAR gZmax = root:HTXRD:gZmax
	NVAR gTthMin = root:HTXRD:gTthMin
	NVAR gTthMax = root:HTXRD:gTthMax
	NVAR gTMin = root:HTXRD:gTMin
	NVAR gTMax = root:HTXRD:gTMax
	SVAR gCtab = root:HTXRD:gCtab
	Wave tempEdges = root:HTXRD:tempEdges

	// 表示用行列 (log オプション)
	Duplicate/O matRaw, root:HTXRD:matHeat
	Wave matHeat = root:HTXRD:matHeat
	if(gLog)
		matHeat = log(max(matRaw[p][q], 1))
	endif

	String ctab = gCtab
	if(WhichListItem(ctab, CTabList()) < 0)
		ctab = "Rainbow"
	endif

	DoWindow/K HTXRD_Heat
	Display/K=1/N=HTXRD_Heat as "HT-XRD heatmap"
	AppendImage/W=HTXRD_Heat matHeat vs {*, tempEdges}
	if(gZauto)
		ModifyImage/W=HTXRD_Heat matHeat ctab={*, *, $ctab, 0}
	else
		ModifyImage/W=HTXRD_Heat matHeat ctab={gZmin, gZmax, $ctab, 0}
	endif

	HTXRD_ApplyStyle("HTXRD_Heat")
	Variable wpt = gFigW * kCM2PT
	Variable hpt = gHeatH * kCM2PT
	ModifyGraph/W=HTXRD_Heat width=wpt, height=hpt
	String lbl = HTXRD_TthLabel()
	Label/W=HTXRD_Heat bottom lbl
	Label/W=HTXRD_Heat left "Temperature / K"
	SetAxis/W=HTXRD_Heat bottom gTthMin, gTthMax
	SetAxis/W=HTXRD_Heat left gTMin, gTMax

	if(gCbar)
		ModifyGraph/W=HTXRD_Heat margin(right)=80
		if(gLog)
			ColorScale/W=HTXRD_Heat/C/N=cb/F=0/B=1/A=RC/X=-18.0/Y=0.0 image=matHeat, width=10, heightPct=70, tickLen=2, frame=0.00, "log\\B10\\M(Intensity / counts)"
		else
			ColorScale/W=HTXRD_Heat/C/N=cb/F=0/B=1/A=RC/X=-18.0/Y=0.0 image=matHeat, width=10, heightPct=70, tickLen=2, frame=0.00, "Intensity / counts"
		endif
	endif
	return 0
End

// ============================================================================
//  3. CIF parsing
// ============================================================================

// 1行をトークン分割 (引用符 '...' "..." 対応)。tokens は text wave に格納
static Function HTXRD_CIF_Tokenize(str, wTok)
	String str
	Wave/T wTok
	Variable i = 0, n = strlen(str), cnt = numpnts(wTok), cc
	String tok, q
	do
		// skip whitespace
		do
			if(i >= n)
				break
			endif
			cc = char2num(str[i, i])
			if(cc == 32 || cc == 9 || cc == 13 || cc == 10)
				i += 1
			else
				break
			endif
		while(1)
		if(i >= n)
			break
		endif
		tok = ""
		cc = char2num(str[i, i])
		if(cc == 39 || cc == 34)		// ' or "
			q = str[i, i]
			i += 1
			do
				if(i >= n)
					break
				endif
				if(CmpStr(str[i, i], q) == 0)
					i += 1
					break
				endif
				tok += str[i, i]
				i += 1
			while(1)
		else
			do
				if(i >= n)
					break
				endif
				cc = char2num(str[i, i])
				if(cc == 32 || cc == 9 || cc == 13 || cc == 10)
					break
				endif
				tok += str[i, i]
				i += 1
			while(1)
		endif
		cnt += 1
		Redimension/N=(cnt) wTok
		wTok[cnt - 1] = tok
	while(1)
	return cnt
End

// "1.2345(6)" → 1.2345
static Function HTXRD_CIFNum(s)
	String s
	Variable i = strsearch(s, "(", 0)
	if(i >= 0)
		s = s[0, i - 1]
	endif
	return str2num(s)
End

// 対称操作の1成分 ("-x+1/2" 等) を評価
static Function HTXRD_EvalSymComp(expr, xx, yy, zz)
	String expr
	Variable xx, yy, zz
	Variable i = 0, n = strlen(expr)
	Variable val = 0, sgn = 1, coef = NaN, num, cc
	String numstr
	do
		if(i >= n)
			break
		endif
		cc = char2num(expr[i, i])
		if(cc == 32 || cc == 9)
			i += 1
		elseif(cc == 43)		// +
			if(numtype(coef) == 0)
				val += sgn * coef
				coef = NaN
			endif
			sgn = 1
			i += 1
		elseif(cc == 45)		// -
			if(numtype(coef) == 0)
				val += sgn * coef
				coef = NaN
			endif
			sgn = -1
			i += 1
		elseif(cc == 120 || cc == 88)	// x
			val += sgn * (numtype(coef) == 0 ? coef : 1) * xx
			coef = NaN
			sgn = 1
			i += 1
		elseif(cc == 121 || cc == 89)	// y
			val += sgn * (numtype(coef) == 0 ? coef : 1) * yy
			coef = NaN
			sgn = 1
			i += 1
		elseif(cc == 122 || cc == 90)	// z
			val += sgn * (numtype(coef) == 0 ? coef : 1) * zz
			coef = NaN
			sgn = 1
			i += 1
		elseif((cc >= 48 && cc <= 57) || cc == 46)	// number (or fraction)
			numstr = ""
			do
				if(i >= n)
					break
				endif
				cc = char2num(expr[i, i])
				if((cc >= 48 && cc <= 57) || cc == 46)
					numstr += expr[i, i]
					i += 1
				else
					break
				endif
			while(1)
			num = str2num(numstr)
			if(i < n)
				if(char2num(expr[i, i]) == 47)	// '/'
					i += 1
					numstr = ""
					do
						if(i >= n)
							break
						endif
						cc = char2num(expr[i, i])
						if((cc >= 48 && cc <= 57) || cc == 46)
							numstr += expr[i, i]
							i += 1
						else
							break
						endif
					while(1)
					num /= str2num(numstr)
				endif
			endif
			coef = num
		else
			i += 1		// '*' など無視
		endif
	while(1)
	if(numtype(coef) == 0)
		val += sgn * coef
	endif
	return val
End

static Function HTXRD_FindCol(wCols, tag)
	Wave/T wCols
	String tag
	Variable i, n = numpnts(wCols)
	for(i = 0; i < n; i += 1)
		if(CmpStr(wCols[i], tag) == 0)
			return i
		endif
	endfor
	return -1
End

// CIF ファイルを読み, root:HTXRD:cif<slot> に
// セル定数(変数) と 展開済み原子座標 (eX,eY,eZ,eOcc,eEl) を作る
Function HTXRD_LoadCIF(slot)
	Variable slot
	HTXRD_Init()
	Variable refNum
	String fileFilter = "CIF Files (*.cif):.cif;All Files:.*;"
	Open/D/R/F=fileFilter refNum
	String fname = S_fileName
	if(strlen(fname) == 0)
		return -1
	endif

	// ---- read all lines ----
	Make/O/T/N=0 root:HTXRD:cifLines
	Wave/T cifLines = root:HTXRD:cifLines
	Open/R refNum as fname
	String line
	String bom = num2char(0xEF) + num2char(0xBB) + num2char(0xBF)
	Variable nl = 0
	do
		FReadLine refNum, line
		if(strlen(line) == 0)
			break
		endif
		nl += 1
		if(nl == 1)
			if(CmpStr(line[0, 2], bom) == 0)	// UTF-8 BOM を除去
				line = line[3, strlen(line) - 1]
			endif
		endif
		Redimension/N=(nl) cifLines
		cifLines[nl - 1] = TrimString(line)
	while(1)
	Close refNum

	// ---- parse ----
	Variable cA = NaN, cB = NaN, cC = NaN, al = NaN, be = NaN, ga = NaN
	String phName = ""
	Make/O/T/N=0 root:HTXRD:symOps
	Wave/T symOps = root:HTXRD:symOps
	Make/O/T/N=0 root:HTXRD:siteElem
	Wave/T siteElem = root:HTXRD:siteElem
	Make/O/N=0 root:HTXRD:siteX, root:HTXRD:siteY, root:HTXRD:siteZ, root:HTXRD:siteOcc
	Wave siteX = root:HTXRD:siteX
	Wave siteY = root:HTXRD:siteY
	Wave siteZ = root:HTXRD:siteZ
	Wave siteOcc = root:HTXRD:siteOcc
	Make/O/T/N=0 root:HTXRD:wTok
	Wave/T wTok = root:HTXRD:wTok
	Make/O/T/N=0 root:HTXRD:wCols
	Wave/T wCols = root:HTXRD:wCols

	Variable i = 0, j, ncols, ntok, mode, nsym = 0, nsite = 0
	Variable ixSym, ixX, ixY, ixZ, ixOcc, ixTyp, ixLab, ixEl
	String tag, val, esym
	do
		if(i >= nl)
			break
		endif
		line = cifLines[i]
		if(strlen(line) == 0 || CmpStr(line[0, 0], "#") == 0)
			i += 1
			continue
		endif
		if(CmpStr(line[0, 0], ";") == 0)		// multi-line text block: skip
			i += 1
			do
				if(i >= nl)
					break
				endif
				val = cifLines[i]
				if(CmpStr(val[0, 0], ";") == 0)
					i += 1
					break
				endif
				i += 1
			while(1)
			continue
		endif
		if(strlen(line) >= 5 && CmpStr(line[0, 4], "data_") == 0)
			phName = line[5, strlen(line) - 1]
			i += 1
			continue
		endif
		if(strlen(line) >= 5 && CmpStr(line[0, 4], "loop_") == 0)
			// ---- collect column names ----
			i += 1
			Redimension/N=0 wCols
			ncols = 0
			do
				if(i >= nl)
					break
				endif
				line = cifLines[i]
				if(strlen(line) > 0 && CmpStr(line[0, 0], "_") == 0)
					Redimension/N=0 wTok
					HTXRD_CIF_Tokenize(line, wTok)
					ncols += 1
					Redimension/N=(ncols) wCols
					wCols[ncols - 1] = wTok[0]
					i += 1
				else
					break
				endif
			while(1)
			if(ncols == 0)
				continue
			endif
			// ---- what loop is this? ----
			ixSym = HTXRD_FindCol(wCols, "_space_group_symop_operation_xyz")
			if(ixSym < 0)
				ixSym = HTXRD_FindCol(wCols, "_symmetry_equiv_pos_as_xyz")
			endif
			ixX = HTXRD_FindCol(wCols, "_atom_site_fract_x")
			ixY = HTXRD_FindCol(wCols, "_atom_site_fract_y")
			ixZ = HTXRD_FindCol(wCols, "_atom_site_fract_z")
			ixOcc = HTXRD_FindCol(wCols, "_atom_site_occupancy")
			ixTyp = HTXRD_FindCol(wCols, "_atom_site_type_symbol")
			ixLab = HTXRD_FindCol(wCols, "_atom_site_label")
			mode = 0
			if(ixSym >= 0)
				mode = 1
			elseif(ixX >= 0 && ixY >= 0 && ixZ >= 0)
				mode = 2
			endif
			// ---- data rows ----
			do
				if(i >= nl)
					break
				endif
				line = cifLines[i]
				if(strlen(line) == 0)
					i += 1
					continue
				endif
				if(CmpStr(line[0, 0], "_") == 0 || CmpStr(line[0, 0], "#") == 0)
					break
				endif
				if(strlen(line) >= 5 && (CmpStr(line[0, 4], "loop_") == 0 || CmpStr(line[0, 4], "data_") == 0))
					break
				endif
				// accumulate tokens over lines until >= ncols
				Redimension/N=0 wTok
				ntok = HTXRD_CIF_Tokenize(line, wTok)
				do
					if(ntok >= ncols)
						break
					endif
					if(i + 1 >= nl)
						break
					endif
					val = cifLines[i + 1]
					if(strlen(val) == 0)
						break
					endif
					if(CmpStr(val[0, 0], "_") == 0)
						break
					endif
					i += 1
					ntok = HTXRD_CIF_Tokenize(val, wTok)
				while(1)
				i += 1
				if(ntok < ncols)
					continue
				endif
				if(mode == 1)
					nsym += 1
					Redimension/N=(nsym) symOps
					symOps[nsym - 1] = wTok[ixSym]
				elseif(mode == 2)
					nsite += 1
					Redimension/N=(nsite) siteX, siteY, siteZ, siteOcc, siteElem
					siteX[nsite - 1] = HTXRD_CIFNum(wTok[ixX])
					siteY[nsite - 1] = HTXRD_CIFNum(wTok[ixY])
					siteZ[nsite - 1] = HTXRD_CIFNum(wTok[ixZ])
					if(ixOcc >= 0)
						siteOcc[nsite - 1] = HTXRD_CIFNum(wTok[ixOcc])
						if(numtype(siteOcc[nsite - 1]) != 0)
							siteOcc[nsite - 1] = 1
						endif
					else
						siteOcc[nsite - 1] = 1
					endif
					if(ixTyp >= 0)
						siteElem[nsite - 1] = HTXRD_ElemFromStr(wTok[ixTyp])
					else
						siteElem[nsite - 1] = HTXRD_ElemFromStr(wTok[ixLab])
					endif
				endif
			while(1)
			continue
		endif
		if(CmpStr(line[0, 0], "_") == 0)
			// single tag-value
			Redimension/N=0 wTok
			ntok = HTXRD_CIF_Tokenize(line, wTok)
			tag = wTok[0]
			if(ntok >= 2)
				val = wTok[1]
			else
				val = ""
			endif
			if(CmpStr(tag, "_cell_length_a") == 0)
				cA = HTXRD_CIFNum(val)
			elseif(CmpStr(tag, "_cell_length_b") == 0)
				cB = HTXRD_CIFNum(val)
			elseif(CmpStr(tag, "_cell_length_c") == 0)
				cC = HTXRD_CIFNum(val)
			elseif(CmpStr(tag, "_cell_angle_alpha") == 0)
				al = HTXRD_CIFNum(val)
			elseif(CmpStr(tag, "_cell_angle_beta") == 0)
				be = HTXRD_CIFNum(val)
			elseif(CmpStr(tag, "_cell_angle_gamma") == 0)
				ga = HTXRD_CIFNum(val)
			endif
			i += 1
			continue
		endif
		i += 1
	while(1)

	// ---- validate ----
	if(numtype(cA) || numtype(cB) || numtype(cC) || numtype(al) || numtype(be) || numtype(ga))
		DoAlert 0, "CIF のセル定数を読み取れませんでした"
		return -1
	endif
	if(nsite == 0)
		DoAlert 0, "CIF の原子座標 (_atom_site_fract_*) を読み取れませんでした"
		return -1
	endif
	if(nsym == 0)
		Redimension/N=1 symOps
		symOps[0] = "x, y, z"
		Print "HTXRD: 対称操作が無いので P1 として扱います"
	endif
	// element check
	for(i = 0; i < nsite; i += 1)
		if(HTXRD_ElemIdx(siteElem[i]) < 0)
			DoAlert 0, "散乱因子テーブルに無い元素: " + siteElem[i]
			return -1
		endif
	endfor

	// ---- expand atoms by symmetry ----
	String dfn = "cif" + num2istr(slot)
	NewDataFolder/O root:HTXRD:$dfn
	String base = "root:HTXRD:" + dfn + ":"
	Make/O/N=0 $(base + "eX"), $(base + "eY"), $(base + "eZ"), $(base + "eOcc"), $(base + "eEl")
	Wave eX = $(base + "eX")
	Wave eY = $(base + "eY")
	Wave eZ = $(base + "eZ")
	Wave eOcc = $(base + "eOcc")
	Wave eEl = $(base + "eEl")
	Variable nex = 0, k, s0, dup
	Variable px, py, pz, dx, dy, dz
	String op
	for(i = 0; i < nsite; i += 1)
		s0 = nex		// この site の orbit 開始位置
		for(j = 0; j < numpnts(symOps); j += 1)
			op = symOps[j]
			px = HTXRD_EvalSymComp(StringFromList(0, op, ","), siteX[i], siteY[i], siteZ[i])
			py = HTXRD_EvalSymComp(StringFromList(1, op, ","), siteX[i], siteY[i], siteZ[i])
			pz = HTXRD_EvalSymComp(StringFromList(2, op, ","), siteX[i], siteY[i], siteZ[i])
			px -= floor(px)
			py -= floor(py)
			pz -= floor(pz)
			// duplicate check within this site orbit (periodic min-image)
			dup = 0
			for(k = s0; k < nex; k += 1)
				dx = abs(px - eX[k])
				dx = min(dx, 1 - dx)
				dy = abs(py - eY[k])
				dy = min(dy, 1 - dy)
				dz = abs(pz - eZ[k])
				dz = min(dz, 1 - dz)
				if(dx < 1e-3 && dy < 1e-3 && dz < 1e-3)
					dup = 1
					break
				endif
			endfor
			if(!dup)
				nex += 1
				Redimension/N=(nex) eX, eY, eZ, eOcc, eEl
				eX[nex - 1] = px
				eY[nex - 1] = py
				eZ[nex - 1] = pz
				eOcc[nex - 1] = siteOcc[i]
				eEl[nex - 1] = HTXRD_ElemIdx(siteElem[i])
			endif
		endfor
	endfor

	// ---- store cell & name ----
	Variable/G $(base + "cA") = cA
	Variable/G $(base + "cB") = cB
	Variable/G $(base + "cC") = cC
	Variable/G $(base + "al") = al
	Variable/G $(base + "be") = be
	Variable/G $(base + "ga") = ga
	if(strlen(phName) == 0)
		phName = ParseFilePath(3, fname, ":", 0, 0)
	endif
	String/G $(base + "sName") = phName
	NVAR loadFlag = $("root:HTXRD:gCIFload" + num2istr(slot))
	loadFlag = 1
	SVAR nameStr = $("root:HTXRD:gCIFn" + num2istr(slot))
	sprintf line, "%s  (a=%.4f b=%.4f c=%.4f, %d atoms/cell)", phName, cA, cB, cC, nex
	nameStr = line
	Printf "HTXRD: CIF%d loaded: %s\r", slot + 1, line

	// すぐ計算しておく
	HTXRD_CalcPattern(slot)
	return 0
End

Function HTXRD_ClearCIFs()
	Variable s
	for(s = 0; s < 3; s += 1)
		NVAR/Z fl = $("root:HTXRD:gCIFload" + num2istr(s))
		if(NVAR_Exists(fl))
			fl = 0
		endif
		SVAR/Z ns = $("root:HTXRD:gCIFn" + num2istr(s))
		if(SVAR_Exists(ns))
			ns = "(empty)"
		endif
		KillDataFolder/Z $("root:HTXRD:cif" + num2istr(s))
		KillWaves/Z $("root:HTXRD:cifProf" + num2istr(s))
	endfor
End

// ============================================================================
//  3b. Powder pattern calculation
//  I(hkl) = |F|^2 * LP,  LP = (1+cos^2 2θ)/(sin^2 θ cos θ)   (pymatgen と同一)
// ============================================================================

Function HTXRD_CalcPattern(slot)
	Variable slot
	NVAR/Z fl = $("root:HTXRD:gCIFload" + num2istr(slot))
	if(!NVAR_Exists(fl))
		return -1
	endif
	if(fl == 0)
		return -1
	endif
	String base = "root:HTXRD:cif" + num2istr(slot) + ":"
	NVAR cA = $(base + "cA")
	NVAR cB = $(base + "cB")
	NVAR cC = $(base + "cC")
	NVAR al = $(base + "al")
	NVAR be = $(base + "be")
	NVAR ga = $(base + "ga")
	Wave eX = $(base + "eX")
	Wave eY = $(base + "eY")
	Wave eZ = $(base + "eZ")
	Wave eOcc = $(base + "eOcc")
	Wave eEl = $(base + "eEl")
	Wave scZ = root:HTXRD:scZ
	Wave scAB = root:HTXRD:scAB
	NVAR lam = root:HTXRD:gLam
	NVAR cmin = root:HTXRD:gCmin
	NVAR cmax = root:HTXRD:gCmax
	NVAR cstep = root:HTXRD:gCstep
	NVAR fw = root:HTXRD:gFWHM
	NVAR eta = root:HTXRD:gEta

	// ---- reciprocal metric ----
	Variable car = cos(al * pi / 180), cbr = cos(be * pi / 180), cgr = cos(ga * pi / 180)
	Make/D/O/N=(3, 3) root:HTXRD:Gm
	Wave Gm = root:HTXRD:Gm
	Gm[0][0] = cA * cA
	Gm[1][1] = cB * cB
	Gm[2][2] = cC * cC
	Gm[0][1] = cA * cB * cgr
	Gm[1][0] = Gm[0][1]
	Gm[0][2] = cA * cC * cbr
	Gm[2][0] = Gm[0][2]
	Gm[1][2] = cB * cC * car
	Gm[2][1] = Gm[1][2]
	MatrixOp/O root:HTXRD:Gs = Inv(Gm)
	Wave Gs = root:HTXRD:Gs

	Variable thmax = cmax / 2 * pi / 180
	Variable dstarMax = 2 * sin(thmax) / lam
	Variable dstarMin = 2 * sin(cmin / 2 * pi / 180) / lam
	Variable hmax = ceil(dstarMax * cA) + 1
	Variable kmax = ceil(dstarMax * cB) + 1
	Variable lmax = ceil(dstarMax * cC) + 1

	Variable nat = numpnts(eX)
	// unique element list & per-reflection scattering factors
	Make/O/N=0 root:HTXRD:uEl
	Wave uEl = root:HTXRD:uEl
	Variable i, j, nu = 0, found
	for(i = 0; i < nat; i += 1)
		found = 0
		for(j = 0; j < nu; j += 1)
			if(uEl[j] == eEl[i])
				found = 1
				break
			endif
		endfor
		if(!found)
			nu += 1
			Redimension/N=(nu) uEl
			uEl[nu - 1] = eEl[i]
		endif
	endfor
	Make/O/N=(nu) root:HTXRD:uF
	Wave uF = root:HTXRD:uF
	// map atom -> unique index
	Make/O/N=(nat) root:HTXRD:aU
	Wave aU = root:HTXRD:aU
	for(i = 0; i < nat; i += 1)
		for(j = 0; j < nu; j += 1)
			if(uEl[j] == eEl[i])
				aU[i] = j
				break
			endif
		endfor
	endfor

	// ---- peak list accumulation ----
	Variable cap = 4096, npk = 0
	Make/D/O/N=(cap) root:HTXRD:pkT, root:HTXRD:pkI
	Make/O/N=(cap) root:HTXRD:pkA, root:HTXRD:pkB, root:HTXRD:pkC
	Wave pkT = root:HTXRD:pkT
	Wave pkI = root:HTXRD:pkI
	Wave pkA = root:HTXRD:pkA
	Wave pkB = root:HTXRD:pkB
	Wave pkC = root:HTXRD:pkC

	Variable hh, kk, ll, dstar2, dstar, th, tth, s2, lp
	Variable are, aim, ph, ei, ff, inten
	String hklstr
	for(hh = hmax; hh >= -hmax; hh -= 1)
		for(kk = kmax; kk >= -kmax; kk -= 1)
			for(ll = lmax; ll >= -lmax; ll -= 1)
				if(hh == 0 && kk == 0 && ll == 0)
					continue
				endif
				dstar2 = hh * hh * Gs[0][0] + kk * kk * Gs[1][1] + ll * ll * Gs[2][2]
				dstar2 += 2 * hh * kk * Gs[0][1] + 2 * hh * ll * Gs[0][2] + 2 * kk * ll * Gs[1][2]
				dstar = sqrt(dstar2)
				if(dstar > dstarMax || dstar < dstarMin)
					continue
				endif
				th = asin(lam * dstar / 2)
				tth = 2 * th * 180 / pi
				s2 = dstar2 / 4
				// scattering factors for this reflection
				for(j = 0; j < nu; j += 1)
					ei = uEl[j]
					ff = scAB[ei][0] * exp(-scAB[ei][1] * s2) + scAB[ei][2] * exp(-scAB[ei][3] * s2)
					ff += scAB[ei][4] * exp(-scAB[ei][5] * s2) + scAB[ei][6] * exp(-scAB[ei][7] * s2)
					uF[j] = scZ[ei] - 41.78214 * s2 * ff
				endfor
				// structure factor
				are = 0
				aim = 0
				for(i = 0; i < nat; i += 1)
					ph = 2 * pi * (hh * eX[i] + kk * eY[i] + ll * eZ[i])
					are += eOcc[i] * uF[aU[i]] * cos(ph)
					aim += eOcc[i] * uF[aU[i]] * sin(ph)
				endfor
				lp = (1 + cos(2 * th) ^ 2) / (sin(th) ^ 2 * cos(th))
				inten = (are * are + aim * aim) * lp
				if(inten < 1e-8)
					continue
				endif
				if(npk >= cap)
					cap *= 2
					Redimension/N=(cap) pkT, pkI, pkA, pkB, pkC
				endif
				pkT[npk] = tth
				pkI[npk] = inten
				pkA[npk] = hh
				pkB[npk] = kk
				pkC[npk] = ll
				npk += 1
			endfor
		endfor
	endfor
	Redimension/N=(npk) pkT, pkI, pkA, pkB, pkC
	if(npk == 0)
		DoAlert 0, "指定レンジに反射がありません"
		return -1
	endif

	// ---- merge equivalent reflections (same 2theta) ----
	Sort pkT, pkT, pkI, pkA, pkB, pkC
	String mbase = "root:HTXRD:"
	String ss = num2istr(slot)
	Make/D/O/N=(npk) $(mbase + "cifPk2t" + ss), $(mbase + "cifPkI" + ss)
	Make/O/N=(npk) $(mbase + "cifPkM" + ss)
	Make/O/T/N=(npk) $(mbase + "cifPkHKL" + ss)
	Wave m2t = $(mbase + "cifPk2t" + ss)
	Wave mI = $(mbase + "cifPkI" + ss)
	Wave mM = $(mbase + "cifPkM" + ss)
	Wave/T mH = $(mbase + "cifPkHKL" + ss)
	Make/O/N=(npk) root:HTXRD:mPos		// 代表 hkl が全て非負なら1
	Wave mPos = root:HTXRD:mPos
	Variable nm = 0, isPos
	for(i = 0; i < npk; i += 1)
		isPos = (pkA[i] >= 0 && pkB[i] >= 0 && pkC[i] >= 0)
		sprintf hklstr, "(%d %d %d)", pkA[i], pkB[i], pkC[i]
		if(nm > 0 && abs(pkT[i] - m2t[nm - 1]) < 0.0015)
			mI[nm - 1] += pkI[i]
			mM[nm - 1] += 1
			if(isPos && mPos[nm - 1] == 0)	// 非負の代表 hkl を優先
				mH[nm - 1] = hklstr
				mPos[nm - 1] = 1
			endif
		else
			m2t[nm] = pkT[i]
			mI[nm] = pkI[i]
			mM[nm] = 1
			mH[nm] = hklstr
			mPos[nm] = isPos
			nm += 1
		endif
	endfor
	Redimension/N=(nm) m2t, mI, mM, mH
	// normalize to 100 & drop peaks < 0.01
	Variable mx = WaveMax(mI)
	mI = mI / mx * 100
	Variable nkeep = 0
	for(i = 0; i < nm; i += 1)
		if(mI[i] >= 0.01)
			m2t[nkeep] = m2t[i]
			mI[nkeep] = mI[i]
			mM[nkeep] = mM[i]
			mH[nkeep] = mH[i]
			nkeep += 1
		endif
	endfor
	nm = nkeep
	Redimension/N=(nm) m2t, mI, mM, mH
	KillWaves/Z root:HTXRD:mPos

	// ---- broadened profile (pseudo-Voigt, area-normalized) ----
	Variable ngr = round((cmax - cmin) / cstep) + 1
	Make/O/N=(ngr) $(mbase + "cifProf" + ss)
	Wave prof = $(mbase + "cifProf" + ss)
	SetScale/P x, cmin, cstep, prof
	prof = 0
	Variable gnorm = 2 * sqrt(ln(2) / pi) / fw
	Variable lnorm = 2 / (pi * fw)
	Variable g4 = 4 * ln(2)
	Variable wpts = ceil(fw * 40 / cstep)
	Variable p0, p1, pp, x0, dxr
	for(i = 0; i < nm; i += 1)
		x0 = m2t[i]
		pp = round((x0 - cmin) / cstep)
		p0 = max(0, pp - wpts)
		p1 = min(ngr - 1, pp + wpts)
		for(pp = p0; pp <= p1; pp += 1)
			dxr = (cmin + pp * cstep - x0) / fw
			prof[pp] += mI[i] * (eta * lnorm / (1 + 4 * dxr * dxr) + (1 - eta) * gnorm * exp(-g4 * dxr * dxr))
		endfor
	endfor
	mx = WaveMax(prof)
	if(mx > 0)
		prof = prof / mx * 100
	endif
	Printf "HTXRD: CIF%d pattern: %d reflections -> %d peaks\r", slot + 1, npk, nm
	return 0
End

// slot が読み込み済みなら 1
static Function HTXRD_SlotLoaded(slot)
	Variable slot
	NVAR/Z fl = $("root:HTXRD:gCIFload" + num2istr(slot))
	if(!NVAR_Exists(fl))
		return 0
	endif
	if(fl == 1)
		return 1
	endif
	return 0
End

Function HTXRD_CalcAll()
	Variable s
	for(s = 0; s < 3; s += 1)
		if(HTXRD_SlotLoaded(s))
			HTXRD_CalcPattern(s)
		endif
	endfor
End

static Function HTXRD_SlotColor(slot, rr, gg, bb)
	Variable slot
	Variable &rr, &gg, &bb
	if(slot == 0)
		rr = 0
		gg = 0
		bb = 65535
	elseif(slot == 1)
		rr = 65535
		gg = 0
		bb = 0
	else
		rr = 0
		gg = 39321
		bb = 0
	endif
End

// ============================================================================
//  3c. CIF pattern plot (幅固定, 高さ自由)
// ============================================================================

Function HTXRD_PlotCIFs()
	NVAR gFigW = root:HTXRD:gFigW
	NVAR gCIFh = root:HTXRD:gCIFh
	NVAR cmin = root:HTXRD:gCmin
	NVAR cmax = root:HTXRD:gCmax
	Variable s, nlo = 0, rr, gg, bb, off
	String tn, names = ""
	DoWindow/K HTXRD_CIF
	Display/K=1/N=HTXRD_CIF as "Calculated XRD from CIF"
	for(s = 0; s < 3; s += 1)
		if(!HTXRD_SlotLoaded(s))
			continue
		endif
		Wave/Z prof = $("root:HTXRD:cifProf" + num2istr(s))
		if(!WaveExists(prof))
			continue
		endif
		AppendToGraph/W=HTXRD_CIF prof
		tn = "cifProf" + num2istr(s)
		HTXRD_SlotColor(s, rr, gg, bb)
		ModifyGraph/W=HTXRD_CIF rgb($tn)=(rr, gg, bb), lsize($tn)=1
		off = 110 * nlo
		ModifyGraph/W=HTXRD_CIF offset($tn)={0, off}
		SVAR sName = $("root:HTXRD:cif" + num2istr(s) + ":sName")
		sprintf tn, "\\K(%d,%d,%d)%s", rr, gg, bb, sName
		names = tn + "\r" + names
		nlo += 1
	endfor
	if(nlo == 0)
		DoWindow/K HTXRD_CIF
		DoAlert 0, "CIF が読み込まれていません"
		return -1
	endif
	names = RemoveEnding(names, "\r")
	HTXRD_ApplyStyle("HTXRD_CIF")
	Variable wpt = gFigW * kCM2PT
	Variable hpt = gCIFh * kCM2PT
	ModifyGraph/W=HTXRD_CIF width=wpt, height=hpt
	String lbl = HTXRD_TthLabel()
	Label/W=HTXRD_CIF bottom lbl
	Label/W=HTXRD_CIF left "Intensity / a.u."
	ModifyGraph/W=HTXRD_CIF noLabel(left)=1, nticks(left)=0, minor(left)=0
	Variable ytop = 110 * (nlo - 1) + 115
	SetAxis/W=HTXRD_CIF bottom cmin, cmax
	SetAxis/W=HTXRD_CIF left -4, ytop
	TextBox/W=HTXRD_CIF/C/N=phN/F=0/B=1/A=RT/X=1.00/Y=1.00 names
	return 0
End

// ============================================================================
//  4. Combined figure: heatmap (上) + CIF patterns (下), 2θ軸共有
// ============================================================================

Function HTXRD_MakeCombined()
	Wave/Z matRaw = root:HTXRD:matRaw
	if(!WaveExists(matRaw))
		DoAlert 0, "先に sweep データを読み込んでください"
		return -1
	endif
	NVAR gFigW = root:HTXRD:gFigW
	NVAR gCombH = root:HTXRD:gCombH
	NVAR gFrac = root:HTXRD:gFrac
	NVAR gLog = root:HTXRD:gLog
	NVAR gCbar = root:HTXRD:gCbar
	NVAR gZauto = root:HTXRD:gZauto
	NVAR gZmin = root:HTXRD:gZmin
	NVAR gZmax = root:HTXRD:gZmax
	NVAR gTthMin = root:HTXRD:gTthMin
	NVAR gTthMax = root:HTXRD:gTthMax
	NVAR gTMin = root:HTXRD:gTMin
	NVAR gTMax = root:HTXRD:gTMax
	SVAR gCtab = root:HTXRD:gCtab
	Wave tempEdges = root:HTXRD:tempEdges

	Duplicate/O matRaw, root:HTXRD:matHeat
	Wave matHeat = root:HTXRD:matHeat
	if(gLog)
		matHeat = log(max(matRaw[p][q], 1))
	endif
	String ctab = gCtab
	if(WhichListItem(ctab, CTabList()) < 0)
		ctab = "Rainbow"
	endif

	// CIF が1つでもあれば下段を作る
	Variable s, nlo = 0
	for(s = 0; s < 3; s += 1)
		if(HTXRD_SlotLoaded(s))
			nlo += 1
		endif
	endfor

	DoWindow/K HTXRD_Comb
	Display/K=1/N=HTXRD_Comb as "HT-XRD + calculated patterns"
	AppendImage/W=HTXRD_Comb matHeat vs {*, tempEdges}
	if(gZauto)
		ModifyImage/W=HTXRD_Comb matHeat ctab={*, *, $ctab, 0}
	else
		ModifyImage/W=HTXRD_Comb matHeat ctab={gZmin, gZmax, $ctab, 0}
	endif

	Variable rr, gg, bb, cnt = 0, off
	Variable frLo = gFrac, frHi = gFrac + 0.03
	String tn, names = ""
	if(nlo > 0)
		for(s = 0; s < 3; s += 1)
			if(!HTXRD_SlotLoaded(s))
				continue
			endif
			Wave/Z prof = $("root:HTXRD:cifProf" + num2istr(s))
			if(!WaveExists(prof))
				continue
			endif
			AppendToGraph/W=HTXRD_Comb/L=cifAx prof
			tn = "cifProf" + num2istr(s)
			HTXRD_SlotColor(s, rr, gg, bb)
			ModifyGraph/W=HTXRD_Comb rgb($tn)=(rr, gg, bb), lsize($tn)=1
			off = 110 * cnt
			ModifyGraph/W=HTXRD_Comb offset($tn)={0, off}
			SVAR sName = $("root:HTXRD:cif" + num2istr(s) + ":sName")
			sprintf tn, "\\K(%d,%d,%d)%s", rr, gg, bb, sName
			names = tn + "\r" + names
			cnt += 1
		endfor
		names = RemoveEnding(names, "\r")
		ModifyGraph/W=HTXRD_Comb axisEnab(left)={frHi, 1}
		ModifyGraph/W=HTXRD_Comb axisEnab(cifAx)={0, frLo}
		ModifyGraph/W=HTXRD_Comb freePos(cifAx)=0
		ModifyGraph/W=HTXRD_Comb noLabel(cifAx)=1, nticks(cifAx)=0
		Label/W=HTXRD_Comb cifAx "Intensity / a.u."
		Variable ytop = 110 * (cnt - 1) + 115
		SetAxis/W=HTXRD_Comb cifAx -4, ytop
		TextBox/W=HTXRD_Comb/C/N=phN/F=0/B=1/A=RB/X=1.00/Y=2.00 names
	endif

	HTXRD_ApplyStyle("HTXRD_Comb")
	if(nlo > 0)
		ModifyGraph/W=HTXRD_Comb minor(cifAx)=0
	endif
	Variable wpt = gFigW * kCM2PT
	Variable hpt = gCombH * kCM2PT
	ModifyGraph/W=HTXRD_Comb width=wpt, height=hpt
	String lbl = HTXRD_TthLabel()
	Label/W=HTXRD_Comb bottom lbl
	Label/W=HTXRD_Comb left "Temperature / K"
	SetAxis/W=HTXRD_Comb bottom gTthMin, gTthMax
	SetAxis/W=HTXRD_Comb left gTMin, gTMax
	if(gCbar)
		ModifyGraph/W=HTXRD_Comb margin(right)=80
		if(gLog)
			ColorScale/W=HTXRD_Comb/C/N=cb/F=0/B=1/A=RT/X=-18.0/Y=0.0 image=matHeat, width=10, heightPct=40, tickLen=2, frame=0.00, "log\\B10\\M(Intensity / counts)"
		else
			ColorScale/W=HTXRD_Comb/C/N=cb/F=0/B=1/A=RT/X=-18.0/Y=0.0 image=matHeat, width=10, heightPct=40, tickLen=2, frame=0.00, "Intensity / counts"
		endif
	endif
	return 0
End

// ============================================================================
//  Peak table
// ============================================================================

Function HTXRD_ShowPeakTable(slot)
	Variable slot
	if(!HTXRD_SlotLoaded(slot))
		DoAlert 0, "CIF " + num2istr(slot + 1) + " が読み込まれていません"
		return -1
	endif
	String ss = num2istr(slot)
	Wave m2t = $("root:HTXRD:cifPk2t" + ss)
	Wave mI = $("root:HTXRD:cifPkI" + ss)
	Wave mM = $("root:HTXRD:cifPkM" + ss)
	Wave/T mH = $("root:HTXRD:cifPkHKL" + ss)
	SVAR sName = $("root:HTXRD:cif" + ss + ":sName")
	String wname = "HTXRD_PkTable" + ss
	DoWindow/K $wname
	Edit/K=1/N=$wname m2t, mI, mM, mH as ("Peak list: " + sName)
	return 0
End

// ============================================================================
//  pxt をダブルクリックで開いたとき, コンパイル直後に自動でパネルを開く
// ============================================================================

static Function AfterCompiledHook()
	NVAR/Z opened = root:HTXRD:gPanelOpened
	if(NVAR_Exists(opened))
		return 0
	endif
	Variable/G root:gHTXRDbootstrap = 1		// re-entry guard while panel builds
	HTXRD_OpenPanel()
	Variable/G root:HTXRD:gPanelOpened = 1
	KillVariables/Z root:gHTXRDbootstrap
	return 0
End
