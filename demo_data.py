"""Made-up dataset for the dashboard's hidden sample mode.

A fictional mid-size industrial MRO distributor (two DCs, 14 branches, customer consignment sites).
Every name and id is invented and checked against the live cache so nothing overlaps with real data:
cities, suppliers, items, customers, buyers, PO and receipt numbers.

    python demo_data.py            build data_demo/ (latest.json, history.csv, vendor_terms.json, latest.xlsx)
    python demo_data.py --check    build in memory and only report overlaps with data/latest.json
"""
import csv
import datetime as dt
import json
import math
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DEMO_DIR = ROOT / "data_demo"
SOURCE = "tcp:erp-db01,1433 / daily"           # shown in the sidebar like a live connection
FEEDBACK = "purchasing.analytics@example.com"

TEAM = ["Dana Whitfield", "Marcus Oyelaran", "Priya Raman", "Tom Kessler", "Elena Vasquez"]
BRANCH_SPEC = "Buyer Branch Specific"           # P21 buyer label the dashboard understands

LOCS = [  # (id, name, type, size)
    (820, "Corp Denver DC", "CORP", 1.0), (840, "Corp Columbus DC", "CORP", 0.8),
    (2100, "Denver", "BRANCH", 1.35), (2200, "Kansas City", "BRANCH", 1.1), (2300, "Omaha", "BRANCH", 0.7),
    (2400, "Tulsa", "BRANCH", 0.85), (2500, "Salt Lake City", "BRANCH", 1.0), (2600, "Boise", "BRANCH", 0.6),
    (2700, "Albuquerque", "BRANCH", 0.7), (3100, "Columbus", "BRANCH", 1.25), (3200, "Indianapolis", "BRANCH", 1.0),
    (3300, "Louisville", "BRANCH", 0.8), (3400, "Nashville", "BRANCH", 1.1), (3500, "Memphis", "BRANCH", 0.7),
    (3600, "Charlotte", "BRANCH", 1.15), (3700, "Richmond", "BRANCH", 0.75),
    (2190, "Consignment Denver", "CONSIGNMENT", 0.5), (2590, "Consignment Salt Lake", "CONSIGNMENT", 0.4),
    (3190, "Consignment Columbus", "CONSIGNMENT", 0.5), (3490, "Consignment Nashville", "CONSIGNMENT", 0.35),
    (3690, "Consignment Charlotte", "CONSIGNMENT", 0.4),
]
LOC_FILL = {2100: .91, 2200: .9, 2300: .87, 2400: .88, 2500: .92, 2600: .89, 2700: .84, 3100: .9, 3200: .91,
            3300: .88, 3400: .9, 3500: .82, 3600: .92, 3700: .89}

FR = ["1/4", "5/16", "3/8", "1/2", "5/8", "3/4", "1"]
# group: (cost range, markup, templates) ; a template returns (part, description)
def _g(r):
    c = r.choice
    return {
        "Bearings": ((3, 60), 1.45, [
            lambda: (f"{c([6200, 6201, 6202, 6203, 6204, 6205, 6206, 6304, 6305, 6308])}-{c(['2RS', 'ZZ', 'OPEN'])}",
                     None)]),
        "Mounted Bearings": ((24, 150), 1.4, [lambda: (f"UCP2{c(['04', '05', '06', '07', '08', '10'])}-{c(['12', '16', '20', '24'])}", None)]),
        "Power Transmission": ((6, 95), 1.42, [
            lambda: (f"{c('ABC')}{c(range(26, 128, 4))}", "vbelt"), lambda: (f"{c([40, 50, 60, 80])}R-10", "chain"),
            lambda: (f"{c([40, 50, 60])}B{c(range(12, 36, 2))}", "sprocket")]),
        "Industrial Fasteners": ((4, 42), 1.75, [lambda: (f"HCS{c([5, 8])}-{c(FR)}-{c([1, 1.5, 2, 2.5, 3])}", "hcs"),
                                      lambda: (f"NLN-{c(FR)}", "nut"), lambda: (f"FWS-{c(FR)}", "washer")]),
        "Hydraulic Components": ((2, 130), 1.5, [lambda: (f"H2W-{c(['04', '06', '08', '12'])}", "hose"),
                                       lambda: (f"JIC-{c(['04', '06', '08'])}{c(['FM', 'MM', '90'])}", "jic"),
                                       lambda: (f"HFE-{c([3, 10, 25])}", "filter")]),
        "Pneumatics": ((5, 260), 1.48, [lambda: (f"PTC-{c(['532', '14', '38', '12'])}{c(['N2', 'N4', 'N6'])}", "ptc"),
                                        lambda: (f"ACY-{c([1, 1.5, 2, 3])}x{c([2, 4, 6, 8])}", "cyl"), lambda: (f"FRL-{c(['14', '38', '12'])}", "frl")]),
        "Electrical": ((3, 420), 1.38, [lambda: (f"THHN{c([14, 12, 10, 8])}-{c(['BK', 'WH', 'RD', 'GN'])}", "wire"),
                                        lambda: (f"CTR-{c([9, 12, 18, 25, 32])}A", "contactor"), lambda: (f"DTB-{c([20, 30, 50])}", "tb")]),
        "Motors & Drives": ((280, 3600), 1.2, [lambda: (f"M{c(['1', '2', '3', '5', '7.5', '10'])}-18T", "motor"),
                                                lambda: (f"VFD{c(['1', '2', '3', '5', '10'])}-48", "vfd")]),
        "Lubricants": ((6, 920), 1.45, [lambda: ("EP2-14", "grease"), lambda: (f"GO{c([68, 100, 150, 220, 320])}-5", "gearoil"),
                                        lambda: (f"AW{c([32, 46, 68])}-{c(['5', '55'])}", "hydoil")]),
        "Cutting Tools": ((4, 185), 1.55, [lambda: (f"CDB-{c(FR)}", "drill"), lambda: (f"EM4-{c(FR)}", "endmill"),
                                           lambda: (f"TAP-{c(FR)}", "tap")]),
        "Abrasive Products": ((1.5, 62), 1.6, [lambda: (f"FD{c([45, 5, 7])}-{c([40, 60, 80, 120])}", "flap"),
                                       lambda: (f"CW{c([45, 5, 6])}-045", "cutoff"), lambda: (f"SB{c([1, 2, 4])}x{c([30, 48, 72])}-{c([60, 80, 120])}", "belt")]),
        "Hand Tools": ((6, 230), 1.5, [lambda: (f"CWM-{c(range(8, 33))}", "wrench"), lambda: (f"SKS-38-{c([21, 32, 45])}", "socket"),
                                       lambda: (f"PLL-{c([7, 8, 9])}", "pliers")]),
        "Lifting & Material Handling": ((45, 940), 1.32, [lambda: ("PJ-5527", "pj"), lambda: (f"HT-{c([600, 800])}", "ht"),
                                                lambda: (f"SLG-{c([1, 2, 3])}x{c([4, 6, 8, 10])}", "sling")]),
        "Plumbing & Valves": ((3, 185), 1.5, [lambda: (f"BVB-{c(FR)}", "ballvalve"), lambda: (f"PNB-{c(FR)}x{c([2, 3, 4, 6])}", "nipple"),
                                              lambda: (f"CVB-{c(FR)}", "check")]),
        "Welding Supplies": ((3, 215), 1.42, [lambda: (f"ER70-{c(['035', '045'])}", "mig"), lambda: (f"E7018-{c(['332', '18', '532'])}", "rod"),
                                              lambda: (f"CT-{c(['023', '030', '035'])}", "tip")]),
        "Janitorial": ((12, 78), 1.36, [lambda: (f"TL-{c(['3339', '4046', '4348'])}", "liner"), lambda: ("PT-HW8", "towel"),
                                        lambda: ("DG-CIT1", "degreaser")]),
        "Adhesives & Sealants": ((5, 42), 1.62, [lambda: (f"TLK-{c(['242', '262', '271'])}", "thread"), lambda: ("SIL-CLR", "silicone"),
                                                 lambda: (f"EPX-{c([5, 30])}", "epoxy")]),
    }


def _desc(r, group, part, kind):
    c = r.choice
    p = part.split("-")
    if group == "Bearings":
        return f"Ball Bearing, {p[0]} {p[1].title() if p[1] != '2RS' else '2RS'} {c([12, 15, 17, 20, 25, 30, 40])}mm Bore"
    if group == "Mounted Bearings":
        return f"Pillow Block Bearing, {p[0]} {int(p[1]) / 16:g}\" Bore Set Screw"
    m = {
        "vbelt": lambda: f"V-Belt, {part} Classical Wrapped", "chain": lambda: f"Roller Chain, #{p[0][:-1]} Riveted 10ft Box",
        "sprocket": lambda: f"Sprocket, {part} {c(FR)}\" Bore Finished", "hcs": lambda: f"Hex Cap Screw, Gr {p[0][3:]} {p[1]}\" x {p[2]}\" Zinc {c([25, 50, 100])}/bx",
        "nut": lambda: f"Nylon Insert Lock Nut, {p[1]}\" Zinc {c([50, 100])}/bx", "washer": lambda: f"Flat Washer, SAE {p[1]}\" Zinc 100/bx",
        "hose": lambda: f"Hydraulic Hose, {int(p[1]) / 16:g}\" 2-Wire {c([2250, 3000, 4000])}psi per ft", "jic": lambda: f"JIC Swivel Fitting, {int(p[1][:2]) / 16:g}\" {c(['Female x Male', 'Male x Male', '90 Elbow'])}",
        "filter": lambda: f"Hydraulic Filter Element, {p[1]} Micron", "ptc": lambda: f"Push-to-Connect Fitting, {c(['5/32', '1/4', '3/8', '1/2'])}\" Tube x {c(['1/8', '1/4', '3/8'])}\" NPT",
        "cyl": lambda: f"Air Cylinder, {p[1].split('x')[0]}\" Bore x {p[1].split('x')[1]}\" Stroke", "frl": lambda: f"FRL Unit, {c(['1/4', '3/8', '1/2'])}\" NPT 150psi",
        "wire": lambda: f"Wire, THHN {part[4:6]} AWG Stranded {dict(BK='Black', WH='White', RD='Red', GN='Green')[p[1]]} 500ft", "contactor": lambda: f"Contactor, {p[1]} 3-Pole 120V Coil",
        "tb": lambda: f"Terminal Block, DIN Rail {p[1]}A Gray", "motor": lambda: f"Motor, {part[1:].split('-')[0]}HP 1800RPM TEFC 208-230/460V",
        "vfd": lambda: f"Variable Frequency Drive, {p[0][3:]}HP 480V 3-Phase", "grease": lambda: "Grease, Lithium EP2 14oz Cartridge",
        "gearoil": lambda: f"Gear Oil, ISO {p[0][2:]} 5gal Pail", "hydoil": lambda: f"Hydraulic Oil, AW{p[0][2:]} {p[1]}gal {'Pail' if p[1] == '5' else 'Drum'}",
        "drill": lambda: f"Drill Bit, Cobalt {p[1]}\" Jobber 135 Split Point", "endmill": lambda: f"End Mill, Carbide {p[1]}\" 4-Flute Square",
        "tap": lambda: f"Tap, HSS {p[1]}\"-{c([13, 16, 18, 20])} Plug", "flap": lambda: f"Flap Disc, {p[0][2:].replace('45', '4-1/2')}\" x 7/8\" {p[1]} Grit Zirconia",
        "cutoff": lambda: f"Cut-Off Wheel, {p[0][2:].replace('45', '4-1/2')}\" x .045\" Type 1", "belt": lambda: f"Sanding Belt, {p[1].split('x')[0] if 'x' in p[1] else p[0][2:]}\" x {c([30, 48, 72])}\" {p[-1]} Grit",
        "wrench": lambda: f"Combination Wrench, {p[1]}mm 12-Point", "socket": lambda: f"Socket Set, 3/8\" Dr {p[2]}pc SAE/Metric",
        "pliers": lambda: f"Pliers, {p[1]}\" Lineman's High Leverage", "pj": lambda: "Pallet Jack, 5500lb 27x48 Forks",
        "ht": lambda: f"Hand Truck, {p[1]}lb Nylon Wheels", "sling": lambda: f"Lifting Sling, {p[1].split('x')[0]}\" x {p[1].split('x')[1]}ft Polyester 2-Ply",
        "ballvalve": lambda: f"Ball Valve, {p[1]}\" Brass Full Port NPT", "nipple": lambda: f"Pipe Nipple, {p[1].split('x')[0]}\" x {p[1].split('x')[1]}\" Black Sch 40",
        "check": lambda: f"Check Valve, {p[1]}\" Bronze Swing", "mig": lambda: f"MIG Wire, ER70S-6 .{p[1]} 33lb Spool",
        "rod": lambda: f"Welding Rod, E7018 {dict({'332': '3/32', '18': '1/8', '532': '5/32'})[p[1]]}\" 50lb Can", "tip": lambda: f"Contact Tip, .{p[1]}\" MIG 10/pk",
        "liner": lambda: f"Trash Liner, {p[1][:2]}x{p[1][2:]} 1.5mil Black 100/cs", "towel": lambda: "Paper Towel, Hardwound 8\" x 800ft 6/cs",
        "degreaser": lambda: "Degreaser, Citrus 1gal 4/cs", "thread": lambda: f"Threadlocker, {dict({'242': 'Medium Blue', '262': 'High Red', '271': 'High Red'})[p[1]]} 50ml",
        "silicone": lambda: "Silicone Sealant, Clear 10.1oz", "epoxy": lambda: f"Epoxy, 2-Part {p[1]}min 25ml",
    }
    return m[kind]()


SUP_A = ["Ridgeline", "Bluestem", "Keystone", "Ironwood", "Harborview", "Prairie Wind", "Granite Ridge", "Cobalt Peak",
         "Trident", "Northgate", "Silverbrook", "Lakeshore", "Pinecrest", "Crestview", "Meridian", "Stonebridge",
         "Westbrook", "Copperline", "Highplains", "Riverbend", "Sterlingwood", "Frontier Line", "Clearbrook", "Eastfield",
         "Wildhorse", "Arrowhead", "Mesa Verde", "Kingsfield", "Badger Creek", "Tallgrass", "Ozark Valley", "Bridgewater",
         "Cascade Point", "Redstone", "Thunder Basin", "Juniper", "Black Mesa", "Pikeview", "Sandhill", "Starline"]
SUP_B = {"Bearings": ["Bearing Co.", "Precision Bearings"], "Mounted Bearings": ["Bearing Co.", "Motion Supply"],
         "Power Transmission": ["Power Transmission", "Drive Systems"], "Industrial Fasteners": ["Fastener Supply", "Bolt & Screw"],
         "Hydraulic Components": ["Hydraulic Components", "Fluid Power"], "Pneumatics": ["Pneumatics", "Air Controls"], "Electrical": ["Electric Supply", "Controls Inc."],
         "Motors & Drives": ["Motor Works", "Drives & Automation"], "Lubricants": ["Lubricants", "Oil Company"],
         "Cutting Tools": ["Tool Works", "Cutting Tools"], "Abrasive Products": ["Abrasive Products", "Surface Finishing"], "Hand Tools": ["Tool Company", "Hand Tools Inc."],
         "Lifting & Material Handling": ["Handling Equipment", "Lift & Rigging"], "Plumbing & Valves": ["Valve & Fitting", "Pipe Supply"],
         "Welding Supplies": ["Welding Supply", "Weld Products"], "Janitorial": ["Sanitary Supply", "Facility Products"],
         "Adhesives & Sealants": ["Adhesives", "Chemical Products"]}
CUST_A = ["Granite Peak", "Prairie Line", "Red Rock", "Lakeview", "Iron Creek", "Blue Ridge", "Cedar Hollow", "Northstar",
          "Pioneer Valley", "Willow Bend", "Canyon Ridge", "Harvest Moon", "Union Point", "Heartland", "Front Range", "Twin Oaks",
          "Old Mill", "Bison Trail", "Gold Creek", "Sutter Hill", "Big Sky", "Maple Grove", "Silver Lake", "High Desert",
          "Elk River", "Stony Point", "Quarry Hill", "Foxhollow", "Kettle Creek", "Long Meadow"]
CUST_B = ["Mechanical", "Plant Services", "Packaging", "Foods", "Machining", "Fabrication", "Contractors", "Utilities",
          "Millwork", "Plastics", "Logistics", "Brewing Co.", "Paper Products", "Ag Equipment", "Rail Services",
          "Water District", "Precision", "Metal Works", "HVAC", "Aggregates", "Bottling", "Feed & Grain"]
FIRST = ["Jordan", "Riley", "Avery", "Cameron", "Morgan", "Hayden", "Peyton", "Rowan", "Sawyer", "Emerson", "Finley", "Reese",
         "Kendall", "Blake", "Dakota", "Ellis", "Harper", "Jules", "Kai", "Lane", "Marlow", "Noel", "Quincy", "Shea"]
LAST = ["Abernathy", "Brightwater", "Castellano", "Delacroix", "Easterbrook", "Fairweather", "Galloway", "Hollister",
        "Ingersoll", "Jablonski", "Kowalczyk", "Lindqvist", "Montague", "Nakashima", "Okonkwo", "Pemberton", "Quintero",
        "Rasmussen", "Sorensen", "Thibodeaux", "Underhill", "Vandermeer", "Wexler", "Yarborough"]
POLICIES = [
    (30, 0.15, "Returns accepted within 30 days of invoice with RMA. Unused, original packaging only. 15% restocking fee."),
    (60, 0.10, "RMA required. Stock items returnable within 60 days in resalable condition. 10% restock fee; special orders non-returnable."),
    (90, None, "Stock items returnable within 90 days for full credit with prior authorization. Freight paid by customer."),
    (90, 0.20, "Returns within 90 days with RMA. 20% restocking fee. Cut lengths, chemicals and custom items are not returnable."),
    (45, 0.25, "Authorized returns only, within 45 days. 25% restocking fee applies to all returns."),
]


def iso(d):
    return d.isoformat() if d else None


def build(today: dt.date | None = None, seed: int = 11):
    r = random.Random(seed)
    today = today or dt.date.today()
    params = {"company_id": 1, "dead_days": 365, "slow_days": 180, "aging_days": 90, "usage_months": 6,
              "top_n_per_group": 5, "top_n_overall": 25, "change_days": 70, "require_max": 1}
    G = _g(r)
    branches = [l for l in LOCS if l[2] == "BRANCH"]
    corps = [l for l in LOCS if l[2] == "CORP"]
    locname = {l[0]: l[1] for l in LOCS}

    # ---------------- people ----------------
    used = set(TEAM)
    def person():
        while True:
            n = f"{r.choice(FIRST)} {r.choice(LAST)}"
            if n not in used:
                used.add(n); return n
    branch_buyer = {l[0]: person() for l in branches}
    user_id = lambda name: name.upper().replace(" ", "_")

    # ---------------- suppliers ----------------
    sups, sid = [], 5100
    names_a = SUP_A[:]; r.shuffle(names_a)
    ai = 0
    for g in G:
        for k in range(r.randint(4, 7)):
            a = names_a[ai % len(names_a)]; ai += 1
            name = f"{a} {r.choice(SUP_B[g])}"
            if any(s["name"] == name for s in sups):
                name = f"{a} {SUP_B[g][0]} West"
            sid += r.randint(3, 17)
            rp = r.choice(POLICIES) if r.random() < 0.8 else (None, None, None)
            buyer = r.choices(TEAM + [BRANCH_SPEC, None], weights=[24, 20, 19, 17, 12, 7, 1])[0]
            sups.append({"id": sid, "name": name, "group": g, "code": "".join(ch for ch in a.upper() if ch.isalpha())[:3],
                         "lead": max(3, round(r.lognormvariate(math.log(11), 0.45))), "ontime": min(0.99, max(0.52, r.betavariate(9, 2.2))),
                         "fill": min(1.0, max(0.86, r.betavariate(30, 1.4))), "buyer": buyer, "growth": r.choice([-0.22, -0.08, 0.02, 0.05, 0.07, 0.1, 0.12, 0.16, 0.24, 0.38]) + r.uniform(-0.03, 0.03),
                         "ret_days": rp[0], "restock": rp[1], "policy": rp[2], "size": r.lognormvariate(0, 0.9)})
    by_group = {g: [s for s in sups if s["group"] == g] for g in G}

    # ---------------- items ----------------
    items, seen = [], set()
    for g, (crange, markup, tpls) in G.items():
        n_g = {"Industrial Fasteners": 420, "Bearings": 300, "Electrical": 330, "Hydraulic Components": 300, "Motors & Drives": 90,
               "Lifting & Material Handling": 80, "Janitorial": 110}.get(g, 200)
        for _ in range(n_g):
            s = r.choices(by_group[g], weights=[x["size"] for x in by_group[g]])[0]
            for _try in range(6):
                part, kind = r.choice(tpls)()
                iid = f"{s['code']}{part}"
                if iid not in seen:
                    break
            else:
                iid = f"{s['code']}{part}-{r.randint(10, 99)}"
                if iid in seen:
                    continue
            seen.add(iid)
            lo, hi = crange
            cost = round(math.exp(r.uniform(math.log(lo), math.log(hi))), 2)
            desc = _desc(r, g, part, kind) if kind else _desc(r, g, part, None)
            ns = r.random() < 0.1
            items.append({"id": iid, "desc": desc, "group": g, "sup": s, "cost": cost,
                          "markup": markup * r.uniform(0.9, 1.12), "pop": r.lognormvariate(0, 1.15), "ns": ns})
    # ABC from company demand value
    for it in items:
        it["D"] = it["pop"] * 260 / it["cost"] ** 0.75          # company units / month, rescaled below
    ranked = sorted(items, key=lambda x: -x["D"] * x["cost"])
    for i, it in enumerate(ranked):
        q = i / len(ranked)
        first = "A" if q < 0.08 else "B" if q < 0.25 else "C" if q < 0.55 else "D"
        second = r.choice({"A": "AAB", "B": "ABBC", "C": "BCCD", "D": "CDD"}[first])
        it["abc"] = "NS" if it["ns"] else (None if r.random() < 0.06 else first + second)
        it["prank"] = 1 - q

    # ---------------- item-locations ----------------
    sumsize = sum(l[3] for l in branches)
    IL = []
    for l in LOCS:
        lid, lname, ltype, size = l
        for it in items:
            if ltype == "BRANCH":
                p = (0.12 + 0.62 * it["prank"]) * (0.75 + 0.25 * size)
                if it["ns"]:
                    p *= 0.25
            elif ltype == "CORP":
                p = 0.02 + 0.22 * it["prank"] ** 2 * size
            else:
                p = 0.004 + 0.05 * it["prank"] ** 3 * size
            if r.random() > p:
                continue
            IL.append({"it": it, "loc": lid, "type": ltype, "size": size})
    for il in IL:
        it = il["it"]
        if il["type"] != "BRANCH":
            il["d"] = 0.0
            continue
        il["d"] = it["D"] * il["size"] / sumsize * 3.2 * r.lognormvariate(0, 0.55)
    # status
    for il in IL:
        it, t = il["it"], il["type"]
        if t == "CONSIGNMENT":
            il["status"], il["rank"] = "CONSIGNMENT", -1
            il["dss"] = r.choice([None, r.randint(5, 400)])
            continue
        if t == "CORP":
            il["status"], il["rank"] = "CORP", 0
            il["dss"] = None if r.random() < 0.5 else r.randint(1, 600)
            continue
        dead_p = 0.32 - 0.26 * it["prank"] + (0.4 if it["ns"] else 0)
        x = r.random()
        if x < dead_p:
            st = "DEAD"
        elif x < dead_p + 0.1:
            st = "SLOW"
        elif x < dead_p + 0.22:
            st = "AGING"
        else:
            st = "ACTIVE"
        il["status"] = st
        il["rank"] = {"DEAD": 4, "SLOW": 3, "AGING": 2, "ACTIVE": 1}[st]
        il["dss"] = {"ACTIVE": int(min(89, r.expovariate(1 / max(1.5, 20 / (1 + il["d"]))))), "AGING": r.randint(90, 179),
                     "SLOW": r.randint(180, 364), "DEAD": None if r.random() < 0.22 else r.randint(365, 1500)}[st]
        il["d"] *= {"ACTIVE": 1, "AGING": 0.35, "SLOW": 0.12, "DEAD": 0}[st]
    # stocking parameters and quantities (raw scale)
    for il in IL:
        it, s = il["it"], il["it"]["sup"]
        d = il["d"]
        lt = s["lead"] / 30.4
        stocked_ok = not it["ns"] and it["abc"] != "NS" and il["type"] in ("BRANCH", "CORP")
        if il["type"] == "CORP":
            il["min"], il["max"] = (it["D"] * 0.25 * il["size"], it["D"] * 0.6 * il["size"]) if stocked_ok and r.random() < 0.7 else (0, 0)
            il["qty"] = it["D"] * 0.8 * il["size"] * r.lognormvariate(0, 0.6)
        elif il["type"] == "CONSIGNMENT":
            il["min"] = il["max"] = 0
            il["qty"] = it["D"] * 5.5 * il["size"] * r.lognormvariate(0, 0.7)
        else:
            if stocked_ok and il["status"] in ("ACTIVE", "AGING") and r.random() < 0.93:
                mn = d * (lt + 0.5)
                if r.random() < 0.1:
                    mn = d * lt * 0.55            # min that doesn't cover lead-time demand
                il["min"] = max(1, math.ceil(mn))
                il["max"] = il["min"] + max(1, math.ceil(d * r.uniform(0.9, 2.2)))
            elif stocked_ok and il["status"] in ("SLOW", "DEAD") and r.random() < 0.35:
                il["min"] = r.randint(1, 6); il["max"] = il["min"] + r.randint(2, 12)
            else:
                il["min"] = il["max"] = 0
            if il["status"] == "ACTIVE":
                months = r.uniform(1.0, 3.6) if r.random() > 0.1 else r.uniform(6, 14)
                il["qty"] = max(1, d * months)
            elif il["status"] == "AGING":
                il["qty"] = max(1, d * r.uniform(2, 6) + r.uniform(0, 4))
            else:
                il["qty"] = max(1, it["D"] * il["size"] / sumsize * 3.2 * r.uniform(0.4, 1.6) * (3.2 if il["status"] == "DEAD" else 1.7))
        il["stocked"] = stocked_ok and il["max"] > 0
    # scale to a ~$15M inventory
    raw = sum(il["qty"] * il["it"]["cost"] for il in IL)
    k = 15.2e6 / raw
    for il in IL:
        il["qty"] *= k; il["d"] *= k
        if il["max"]:
            il["min"] = max(1, round(il["min"] * k)); il["max"] = max(il["min"] + 1, round(il["max"] * k))
        else:
            il["min"] = il["max"] = 0
    for it in items:
        it["D"] *= k

    # ---------------- stockouts (branch stocked items) ----------------
    events = []
    win0 = today - dt.timedelta(days=180)
    po_seq = [7_310_000]
    def next_po():
        po_seq[0] += r.randint(1, 4); return po_seq[0]
    for il in IL:
        if il["type"] != "BRANCH" or not il["stocked"] or il["status"] not in ("ACTIVE", "AGING") or il["d"] <= 0:
            continue
        s = il["it"]["sup"]
        lam = 0.06 + 0.8 * (1 - s["ontime"]) + 0.045 * math.log1p(il["d"])
        n = sum(1 for _ in range(6) if r.random() < lam / 6 * 1.4)
        il["events"] = []
        for _ in range(n):
            start = win0 + dt.timedelta(days=r.randint(0, 178))
            e = {"il": il, "start": start}
            ltd = il["d"] / 30.4 * s["lead"]
            has_po = r.random() < 0.6
            if has_po:
                late = r.random() < (1 - s["ontime"]) * 1.7
                po_date = start - dt.timedelta(days=r.randint(1, s["lead"] + 4))
                if late:
                    due = start - dt.timedelta(days=r.randint(0, 9)) if r.random() < 0.6 else start + dt.timedelta(days=r.randint(1, 5))
                    rec = max(due + dt.timedelta(days=r.randint(2, 18)), start + dt.timedelta(days=1))
                else:
                    due = start + dt.timedelta(days=r.randint(1, 14))
                    rec = max(start + dt.timedelta(days=1), due - dt.timedelta(days=r.randint(0, 2)))
                e.update(po=next_po(), po_date=po_date, due=due, rec=rec, end=rec)
            else:
                react = int(r.expovariate(1 / 4))
                nxt = start + dt.timedelta(days=react)
                e.update(next_po=next_po(), next_date=nxt, end=nxt + dt.timedelta(days=max(2, round(s["lead"] * r.uniform(0.7, 1.3)))))
            if e["end"] >= today:
                e["end"] = None
            events.append(e); il["events"].append(e)
    # keep events at one item-location from overlapping
    for il in IL:
        evs = sorted(il.get("events", []), key=lambda e: e["start"])
        keep, last_end = [], None
        for e in evs:
            if last_end and e["start"] <= last_end:
                continue
            keep.append(e); last_end = e["end"] or today
            if e["end"] is None:
                break
        il["events"] = keep
    events = [e for il in IL for e in il.get("events", [])]
    out_now = {id(e["il"]) for e in events if e["end"] is None}

    # ---------------- items result set (A) ----------------
    A, M, layers = [], [], []
    rows_by_loc = {}
    for il in IL:
        it, s, lid = il["it"], il["it"]["sup"], il["loc"]
        if id(il) in out_now:
            il["q"] = 0
            continue
        q = max(1, round(il["qty"]))
        il["q"] = q
        unit = it["cost"]
        cost = round(q * unit * r.uniform(0.96, 1.04), 2)
        il["cost_oh"] = cost
        dss = il["dss"]
        if il["status"] == "ACTIVE":
            dsr = r.randint(1, 60)
        elif il["status"] in ("AGING", "SLOW"):
            dsr = r.randint(30, 420)
        elif il["type"] == "BRANCH":
            dsr = r.randint(3, 50) if r.random() < 0.08 else r.randint(200, 1500)
        else:
            dsr = r.randint(5, 700)
        il["dsr"] = dsr
        oldest = dsr + (r.randint(0, 120) if il["status"] == "ACTIVE" else r.randint(0, 500))
        older = r.randint(1, 3) if oldest >= params["dead_days"] else 0
        oq = round(q * r.uniform(0.3, 1)) if older else 0
        usage6 = round(il["d"] * 6)
        doh = round(q / (usage6 / 130), 1) if usage6 else None
        dept = None
        if il["type"] == "CONSIGNMENT":
            lb, dept, po = None, None, None
        elif il["type"] == "CORP" or r.random() < 0.55:
            lb = s["buyer"] if s["buyer"] in TEAM else r.choice(TEAM)
            dept, po = "Purchasing Department", 7_000_000 + r.randint(0, 309_999)
        else:
            lb, dept, po = branch_buyer[lid], "Branch", 7_000_000 + r.randint(0, 309_999)
        A.append([lid, locname[lid], il["type"], it["id"], it["desc"], it["group"], it["abc"], s["id"], s["name"],
                  "N" if it["ns"] else "Y", q, cost, round(unit * r.uniform(1.0, 1.06), 4), il["max"],
                  iso(today - dt.timedelta(days=dsr)), iso(today - dt.timedelta(days=dss)) if dss is not None else None,
                  iso(today - dt.timedelta(days=dsr + 4)), dsr, dss, dsr + 4, iso(today - dt.timedelta(days=oldest)), oldest,
                  older, oq, round(oq * unit, 2), il["rank"], il["status"], usage6, round(il["d"], 4), doh, lb, dept, po])
        # buyer attribution (M)
        picks = [("(Non-PO: TR)", "Non-PO/Trace", "Trace Needed")] if il["type"] == "CONSIGNMENT" else [(lb, dept, "PO Origin")]
        if il["type"] == "BRANCH" and r.random() < 0.25:
            picks.append((r.choice(TEAM) if dept == "Branch" else branch_buyer[lid], "Purchasing Department" if dept == "Branch" else "Branch", "PO Origin"))
        if il["type"] == "BRANCH" and r.random() < 0.12:
            picks.append(("(Non-PO: IA)", "Non-PO/Trace", "Trace Needed"))
        sh = [r.uniform(0.3, 1) for _ in picks]; tot = sum(sh)
        for (b, dp, org), w in zip(picks, sh):
            M.append([lid, it["id"], b, dp, org, r.randint(1, 3), 1 if org == "PO Origin" else 0,
                      po if org == "PO Origin" else None, round(q * w / tot, 4), round(cost * w / tot, 2),
                      iso(today - dt.timedelta(days=oldest)), iso(today - dt.timedelta(days=dsr))])
        layers.append([s["id"], s["name"], 9_100_000 + len(layers), iso(today - dt.timedelta(days=oldest)), oldest,
                       round(unit, 4), round(unit * 1.03, 4), q + r.randint(0, 20), q, cost, lid, locname[lid], il["type"],
                       it["id"], it["desc"], it["abc"], iso(today - dt.timedelta(days=dss)) if dss is not None else None,
                       iso(today - dt.timedelta(days=dsr + 4)), it["group"], "N" if it["ns"] else "Y", il["max"], "IR",
                       po, lb, lb, "PO Origin" if po else "Trace Needed", dept, iso(today - dt.timedelta(days=dsr)), dsr,
                       iso(today - dt.timedelta(days=dss)) if dss is not None else None, dss, iso(today - dt.timedelta(days=dsr + 4)),
                       dsr + 4, 1 if older else 0, il["status"], il["rank"]])
        rows_by_loc.setdefault(lid, 0.0)
        rows_by_loc[lid] += cost
    layers.sort(key=lambda x: -x[9])
    C = [x + [1, i + 1] for i, x in enumerate(layers[:params["top_n_overall"]])]
    # usage at other branches for dead/slow items (transfer targets)
    K = []
    dead_items = {il["it"]["id"] for il in IL if il.get("status") in ("DEAD", "SLOW")}
    have = {(il["it"]["id"], il["loc"]) for il in IL}
    for il in IL:
        if il["it"]["id"] in dead_items and il["type"] == "BRANCH" and il["d"] > 0:
            K.append([il["it"]["id"], il["loc"], round(il["d"] * 6)])
    for iid in list(dead_items)[: len(dead_items) // 3]:
        for l in r.sample(branches, r.randint(0, 2)):
            if (iid, l[0]) not in have:
                K.append([iid, l[0], r.randint(3, 60)])

    ws = dt.date(today.year, today.month, 1)
    for _ in range(params["usage_months"]):
        ws = (ws - dt.timedelta(days=1)).replace(day=1)
    we = dt.date(today.year, today.month, 1) - dt.timedelta(days=1)
    L = [[today.isoformat(), ws.isoformat(), we.isoformat(), 130, 6, 1, 365, 180, 90]]

    # ---------------- modules ----------------
    mods = {}
    def mod(name, cols, rows):
        mods[name] = {"columns": cols, "rows": rows, "seconds": round(r.uniform(0.3, 9) if len(rows) < 5000 else r.uniform(8, 55), 1)}

    price = {it["id"]: round(it["cost"] * it["markup"], 2) for it in items}
    # customers
    custs, cseen = [], set()
    cid = 61_000
    while len(custs) < 520:
        n = f"{r.choice(CUST_A)} {r.choice(CUST_B)}{r.choice(['', '', ' LLC', ' Inc.', ' Co.'])}"
        if n in cseen:
            continue
        cseen.add(n); cid += r.randint(1, 9)
        custs.append((cid, n, r.choice(branches)[0]))
    cash = {l[0]: (60_000 + l[0] // 100, f"Cash Sale - {l[1]} Counter") for l in branches}
    cust_by_loc = {l[0]: [c for c in custs if c[2] == l[0]] or custs[:5] for l in branches}

    # sales_12m, last_customer, fill_rate
    S12, LC, FRr = [], [], []
    sup_sales = {}
    for il in IL:
        if il["type"] != "BRANCH" or (il["d"] <= 0 and il["status"] != "SLOW"):
            continue
        it, lid = il["it"], il["loc"]
        d12 = il["d"] * 12 * r.uniform(0.85, 1.15)
        if il["status"] == "SLOW":
            d12 = max(1, d12)
        qty = max(1, round(d12))
        sales = round(qty * price[it["id"]] * r.uniform(0.95, 1.04), 2)
        cogs = round(qty * it["cost"] * r.uniform(0.98, 1.02), 2)
        per_line = max(1, il["d"] ** 0.5 * r.uniform(0.6, 1.6))
        inv = max(1, round(qty / per_line))
        ncust = max(1, min(inv, round(inv ** 0.65 * r.uniform(0.6, 1.3))))
        last = today - dt.timedelta(days=il["dss"] if il["dss"] is not None else 300)
        S12.append([it["id"], lid, qty, sales, cogs, inv, ncust, iso(last)])
        sup_sales[it["sup"]["id"]] = sup_sales.get(it["sup"]["id"], 0) + sales
        il["lines12"], il["per_line"] = inv, per_line
        pool = cust_by_loc[lid]
        lc = r.choice(pool) if r.random() > 0.12 else cash[lid]
        tc = r.choice(pool)
        LC.append([it["id"], lid, lc[0], lc[1], iso(last), tc[0], tc[1], lid, round(qty * r.uniform(0.2, 0.6))])
    for il in IL:   # last customer on dead stock
        if il["type"] == "BRANCH" and il["status"] == "DEAD" and il["dss"] and r.random() < 0.5:
            c = r.choice(cust_by_loc[il["loc"]])
            LC.append([il["it"]["id"], il["loc"], c[0], c[1], iso(today - dt.timedelta(days=il["dss"])), None, None, None, None])
    mod("sales_12m", ["item_id", "location_id", "qty_sold", "sales", "cogs", "invoices", "customers", "last_invoice_date"], S12)
    mod("last_customer", ["item_id", "location_id", "last_customer_id", "last_customer_name", "last_customer_date", "top_customer_12m_id",
                          "top_customer_12m_name", "top_customer_12m_location", "top_customer_12m_qty"], LC)

    # fill rate (stocked branch items with orders)
    fill_loc = {}
    for il in IL:
        if il["type"] != "BRANCH" or not il["stocked"] or not il.get("lines12"):
            continue
        it, lid = il["it"], il["loc"]
        lines = max(1, round(il["lines12"] / 2 * r.uniform(0.8, 1.2)))
        base = LOC_FILL[lid] + 0.04 * (it["sup"]["ontime"] - 0.8) - 0.05 * len(il.get("events", []))
        missed = sum(1 for _ in range(lines) if r.random() > min(0.995, max(0.4, base)))
        partial = sum(1 for _ in range(missed) if r.random() < 0.09)
        opn = sum(1 for _ in range(missed - partial) if r.random() < 0.08)
        late = missed - partial - opn
        canceled = 1 if r.random() < 0.03 else 0
        qo = round(lines * il["per_line"])
        qf = round(qo * (lines - missed * 0.75) / lines)
        vo = round(qo * price[it["id"]], 2)
        vf = round(vo * qf / max(1, qo), 2)
        cust = max(1, round(lines ** 0.7))
        FRr.append([it["id"], it["desc"], lid, lines, lines - missed, partial, late, opn, canceled,
                    lines - partial - (1 if r.random() < 0.02 else 0), max(1, round(lines * 0.97)), cust,
                    min(cust, max(0, round(missed * 0.8))), qo, qf, vo, vf,
                    round(r.uniform(2.5, 9), 1) if missed else None, iso(today - dt.timedelta(days=r.randint(3, 170))) if missed else None])
        a = fill_loc.setdefault(lid, [0, 0, 0.0, 0.0]); a[0] += lines; a[1] += lines - missed; a[2] += vo; a[3] += vf
    mod("fill_rate", ["item_id", "item_desc", "location_id", "lines", "lines_filled", "lines_partial", "lines_late", "lines_open", "lines_canceled",
                      "lines_first_ship_full", "orders", "customers", "customers_shorted", "qty_ordered", "qty_filled", "value_ordered", "value_filled",
                      "avg_days_to_complete_missed", "last_miss"], FRr)
    FW = []
    monday = today - dt.timedelta(days=today.weekday())
    for w in range(26, -1, -1):
        wk = monday - dt.timedelta(weeks=w)
        for lid, (ln, lf, vo, vf) in fill_loc.items():
            part = 0.45 if w in (26, 0) else 1
            lines = round(ln / 26 * r.uniform(0.85, 1.15) * part)
            rate = min(0.99, lf / ln + r.gauss(0, 0.022))
            FW.append([iso(wk), lid, lines, round(lines * rate), round(vo / 26 * part * r.uniform(0.85, 1.15), 2),
                       round(vo / 26 * part * (vf / vo) * r.uniform(0.95, 1.03), 2)])
    mod("fill_weekly", ["week", "location_id", "lines", "lines_filled", "value_ordered", "value_filled"], FW)

    # stockout events + stockouts
    SE, SO = [], []
    for il in IL:
        evs = il.get("events")
        if not evs:
            continue
        it, s = il["it"], il["it"]["sup"]
        sb = s["buyer"]
        days_tot = 0
        for e in evs:
            end = e["end"]
            days = ((end or today) - e["start"]).days
            days_tot += days
            SE.append([it["id"], it["desc"], il["loc"], iso(e["start"]), iso(end), days, 0 if end else 1, it["abc"],
                       "Min/Max" if r.random() < 0.92 else "OP/OQ", il["min"], il["max"], 0, round(il["d"], 2), it["cost"],
                       s["id"], s["name"], sb, e.get("po"), iso(e.get("po_date")), iso(e.get("due")), iso(e.get("rec")) if end else None,
                       e.get("next_po"), iso(e.get("next_date"))])
        SO.append([it["id"], it["desc"], il["loc"], len(evs), days_tot, iso(evs[-1]["start"]), 1 if evs[-1]["end"] is None else 0])
    mod("stockout_events", ["item_id", "item_desc", "location_id", "out_start", "out_end", "days_out", "ongoing", "purchase_class",
                            "replenishment_method", "inv_min", "inv_max", "safety_stock", "avg_monthly_usage", "unit_cost",
                            "primary_supplier_id", "supplier_name", "supplier_buyer", "open_po_no", "open_po_date", "open_po_due",
                            "open_po_received", "next_po_no", "next_po_date"], SE)
    mod("stockouts", ["item_id", "item_desc", "location_id", "stockout_events", "days_out", "last_stockout_date", "out_now"], SO)

    # open POs, backorders, reorder now
    OP, BO, RN = [], [], []
    po_by = {}
    for il in IL:
        if il["type"] not in ("BRANCH", "CORP"):
            continue
        it, s = il["it"], il["it"]["sup"]
        q = il.get("q", 0)
        on_po = 0
        want = il["stocked"] and (q <= il["min"] * 1.2 or id(il) in out_now)
        risky = il["type"] == "BRANCH" and il["status"] in ("DEAD", "SLOW") and r.random() < 0.02
        if (want and r.random() < 0.7) or (il["stocked"] and r.random() < 0.05) or risky:
            key = (s["id"], il["loc"])
            if key not in po_by or r.random() < 0.25:
                po_by[key] = (next_po(), today - dt.timedelta(days=r.randint(1, int(s["lead"] * 1.8) + 3)))
            po, pod = po_by[key]
            due = pod + dt.timedelta(days=s["lead"] + r.randint(-2, 4))
            on_po = max(1, il["max"] - q) if il["max"] else r.randint(2, 20)
            pt = r.choices(["S", "B", "D", "P"], weights=[64, 17, 10, 9])[0]
            buyer = s["buyer"] if s["buyer"] in TEAM else (branch_buyer.get(il["loc"]) or r.choice(TEAM))
            OP.append([po, sum(1 for x in OP if x[0] == po) + 1, il["loc"], it["id"], it["desc"], s["id"], s["name"], buyer,
                       iso(pod), iso(due), on_po, it["cost"], round(on_po * it["cost"], 2), (today - due).days, pt,
                       1_240_000 + r.randint(0, 99_999) if pt == "D" else None])
        if il["type"] == "BRANCH" and il["stocked"] and (q - 0) < il["min"]:
            alloc = r.randint(0, max(0, q))
            avail = q - alloc
            if avail < il["min"]:
                bo_q = r.randint(1, 30) if q == 0 and r.random() < 0.5 else 0
                RN.append([it["id"], it["desc"], il["loc"], it["abc"], "Min/Max", il["min"], il["max"], q, alloc, bo_q, 0, on_po,
                           avail - bo_q, 0 if on_po else 1, it["cost"], s["id"], s["name"], s["buyer"] or "", iso(today - dt.timedelta(days=il["dss"] or 30))])
        if il["type"] == "BRANCH" and (id(il) in out_now and r.random() < 0.6 or (it["ns"] and r.random() < 0.06) or r.random() < 0.012):
            bo_q = r.randint(1, 60)
            od = r.randint(1, 45)
            BO.append([it["id"], it["desc"], il["loc"], it["abc"] or "NS", "N" if it["ns"] else "Y", q, 0, bo_q, 0, on_po or (bo_q if r.random() < 0.7 else 0),
                       s["id"], s["name"], s["buyer"] if s["buyer"] in TEAM else branch_buyer[il["loc"]], r.randint(1, 3), r.randint(1, 2),
                       iso(today - dt.timedelta(days=od)), od, it["cost"]])
    mod("open_po", ["po_no", "line_no", "location_id", "item_id", "item_desc", "supplier_id", "supplier_name", "buyer", "po_date", "date_due",
                    "qty_open", "unit_cost", "value_open", "days_past_due", "po_type", "sales_order_number"], OP)
    mod("backorders", ["item_id", "item_desc", "location_id", "purchase_class", "stockable", "qty_on_hand", "qty_allocated", "qty_backordered",
                       "qty_in_transit", "qty_on_po", "primary_supplier_id", "supplier_name", "buyer", "open_lines", "open_orders",
                       "oldest_bo_date", "oldest_bo_days", "unit_cost"], BO)
    mod("reorder_now", ["item_id", "item_desc", "location_id", "purchase_class", "replenishment_method", "inv_min", "inv_max", "qty_on_hand",
                        "qty_allocated", "qty_backordered", "qty_in_transit", "qty_on_po", "qty_available", "no_po", "unit_cost",
                        "primary_supplier_id", "supplier_name", "primary_buyer", "last_sale_date"], RN)

    # receipts, flow, returns
    RD, FL, RW = [], [], []
    rc_no = [8_420_000]
    for il in IL:
        if il["type"] == "CONSIGNMENT" or "q" not in il and id(il) not in out_now:
            continue
        it, s, lid = il["it"], il["it"]["sup"], il["loc"]
        unit = it["cost"]
        ship_q = il["d"] * 70 / 30.4 * r.uniform(0.8, 1.2)
        dsr = il.get("dsr", 999)
        rec_q = 0
        if dsr <= 70 or (il["d"] > 0 and r.random() < 0.75):
            rec_q = max(1, round(ship_q * r.uniform(0.75, 1.35))) if il["d"] > 0 else r.randint(1, 12)
            prior = round(unit / (1 + r.choice([0, 0, 0, 0.03, 0.05, 0.08, -0.02])), 4)
            buyer = s["buyer"] if s["buyer"] in TEAM and r.random() < 0.6 else branch_buyer.get(lid, r.choice(TEAM))
            nl = max(1, round(rec_q / max(1, il["d"] * 0.6)))
            RD.append([it["id"], lid, buyer, s["id"], s["name"], min(nl, 9), rec_q, round(rec_q * unit, 2), unit, prior])
            if s["ret_days"] and dsr <= s["ret_days"]:
                rc_no[0] += r.randint(1, 6)
                rd = today - dt.timedelta(days=dsr)
                rb = rd + dt.timedelta(days=s["ret_days"])
                lq = min(il.get("q", 0), rec_q)
                if lq > 0 and (rb - today).days > 0:
                    RW.append([it["id"], lid, rc_no[0], 7_000_000 + r.randint(0, 309_999), iso(rd), lq, round(lq * unit, 2), s["id"], s["name"],
                               buyer, s["ret_days"], s["restock"], s["policy"], iso(rb), (rb - today).days])
        shipped = round(ship_q) * unit
        recv = rec_q * unit
        rma = round(shipped * r.uniform(0, 0.02), 2)
        adj = round(r.gauss(0, 0.01) * (shipped + recv), 2)
        rts = -round(recv * 0.01, 2) if r.random() < 0.05 else 0
        xfer = round(r.choice([0, 0, 0, 1, -1]) * unit * r.randint(1, 10), 2) if il["type"] == "BRANCH" else -round(recv * r.uniform(0.6, 0.95), 2)
        if il["type"] == "CORP":
            shipped = 0
        net = round(recv - shipped + rma + adj + rts + xfer, 2)
        prev_r = round(recv * r.uniform(0.7, 1.15), 2); prev_s = round(shipped * r.uniform(0.85, 1.05), 2)
        FL.append([it["id"], lid, round(recv, 2), rec_q, round(-shipped, 2), -round(ship_q) if il["type"] == "BRANCH" else 0, rma, adj, rts, xfer, net,
                   prev_r, round(-prev_s, 2), round(prev_r - prev_s, 2)])
    mod("receipt_detail", ["item_id", "location_id", "buyer", "supplier_id", "supplier_name", "receipt_lines", "qty", "value", "unit_cost", "prior_unit_cost"], RD)
    mod("inventory_flow", ["item_id", "location_id", "cur_receipts", "cur_receipts_qty", "cur_shipped", "cur_shipped_qty", "cur_returns_in", "cur_adjust",
                           "cur_to_supplier", "cur_transfer", "cur_net", "prev_receipts", "prev_shipped", "prev_net"], FL)
    mod("return_window", ["item_id", "location_id", "receipt_no", "po_no", "date_received", "qty", "value", "supplier_id", "supplier_name", "po_buyer",
                          "return_days", "restock_rate", "return_policy", "return_by", "days_left"], RW)

    # weekly inventory history per location: the last 20 weeks follow the flow module, older weeks a seasonal path
    IH = []
    weeks = [monday - dt.timedelta(weeks=w) for w in range(65, -1, -1)]
    agg = {}
    for f in FL:
        a = agg.setdefault(f[1], [0, 0, 0, 0, 0])
        a[0] += f[2]; a[1] += f[4]; a[2] += f[6] + f[7] + f[8] + f[9]; a[3] += f[11]; a[4] += f[12]
    hist_path = {}
    for lid, *_ in LOCS:
        now_v = rows_by_loc.get(lid, 0)
        IH.append([None, lid, "NOW", round(now_v, 2)])
        a = agg.get(lid, [0, 0, 0, 0, 0])
        vals, v = [], now_v
        for i, wk in enumerate(reversed(weeks)):
            if i < 10:
                rec, shp, oth = a[0] / 10, a[1] / 10, a[2] / 10
            elif i < 20:
                rec, shp, oth = a[3] / 10, a[4] / 10, 0
            else:
                shp = (a[1] or -now_v * 0.06) / 10 * (1 + 0.12 * math.sin(2 * math.pi * i / 52))
                drift = now_v * (0.0016 + 0.004 * math.sin(2 * math.pi * (i + 9) / 30))
                oth = -abs(shp) * 0.01
                rec = -shp + drift - oth
            n_ = r.uniform(0.82, 1.18)
            rec, shp = rec * n_, shp * (2 - n_) if shp else shp
            IH.append([iso(wk), lid, "receipts", round(rec, 2)])
            IH.append([iso(wk), lid, "shipped", round(shp, 2)])
            IH.append([iso(wk), lid, "other", round(oth * r.uniform(0.5, 1.5), 2)])
            v -= rec + shp + oth
            vals.append((wk, max(v, now_v * 0.4)))
        hist_path[lid] = dict(vals)
    mod("inventory_history", ["week_start", "location_id", "flow", "value"], IH)

    # min/max and cost changes
    MM, CC = [], []
    for il in IL:
        if il["type"] != "BRANCH" or not il["stocked"] or r.random() > 0.11:
            continue
        mn, mx = il["min"], il["max"]
        x = r.random()
        if x < 0.55:
            mb, xb = max(0, round(mn / r.uniform(1.15, 1.8))), max(1, round(mx / r.uniform(1.15, 1.8)))
        elif x < 0.85:
            mb, xb = round(mn * r.uniform(1.2, 2)), round(mx * r.uniform(1.2, 2))
        else:
            mb, xb = 0, 0
        who = r.choice(TEAM) if r.random() < 0.7 else branch_buyer[il["loc"]]
        last = today - dt.timedelta(days=r.randint(1, 88))
        meth = ("Up To", "Min/Max") if r.random() < 0.07 else (None, None)
        MM.append([il["it"]["id"], str(il["loc"]), mb, mn, xb, mx, meth[0], meth[1], r.randint(1, 4), user_id(who), who, iso(last),
                   iso(last - dt.timedelta(days=r.randint(0, 30)))])
    hike = {s["id"]: (r.uniform(0.03, 0.08), today - dt.timedelta(days=r.randint(5, 85))) for s in sups if r.random() < 0.35}
    for it in items:
        h = hike.get(it["sup"]["id"])
        if not (h and r.random() < 0.85) and r.random() > 0.08:
            continue
        pct = h[0] * r.uniform(0.8, 1.2) if h else r.uniform(-0.06, 0.1)
        before = round(it["cost"] / (1 + pct), 4)
        who = it["sup"]["buyer"] if it["sup"]["buyer"] in TEAM else r.choice(TEAM)
        when = h[1] if h else today - dt.timedelta(days=r.randint(1, 88))
        after = it["cost"]
        if r.random() < 0.012:                      # an occasional keying slip: decimal or pack-size mix-up
            after = round(after * r.choice([10, 12, 0.1, 0.5, 2.4]), 4)
        n_po = r.randint(0, 14)
        med = round(it["cost"] * r.uniform(0.94, 1.05), 4) if n_po >= 1 else None
        CC.append([it["id"], r.choice(["cost", "standard_cost"]), before, after, before, after, r.randint(1, 2), 0, user_id(who), who, iso(when), med, n_po or None])
    mod("minmax_changes", ["item_id", "location_id", "min_before", "min_after", "max_before", "max_after", "method_before", "method_after", "edits",
                           "changed_by", "changed_by_name", "last_changed", "first_changed"], MM)
    mod("cost_changes", ["item_id", "cost_type", "cost_before", "cost_after", "unit_before", "unit_after", "edits", "locations", "changed_by",
                         "changed_by_name", "last_changed", "po_median_unit", "po_lines_12m"], CC)
    # PO activity per buyer over 180 days, from the open and received PO lines above plus a steady base
    BA = []
    style = {n: (r.uniform(2.2, 4.6), r.uniform(0.6, 0.86), r.uniform(0.005, 0.05)) for n in TEAM}
    for n in TEAM + list(branch_buyer.values()):
        team = n in TEAM
        lpp, ot, canc = style.get(n, (r.uniform(1.4, 2.6), r.uniform(0.55, 0.8), r.uniform(0.01, 0.08)))
        pos = round(r.uniform(900, 2100) if team else r.uniform(120, 650))
        lines = round(pos * lpp)
        judged = round(lines * 0.93)
        BA.append([n, pos, lines, round(lines * canc), round(lines * r.uniform(380, 900), 2), r.randint(25, 70) if team else r.randint(15, 60),
                   r.randint(10, 16) if team else 1, round(lines * (0.85 if team else 0.2)), 0 if team else r.randint(10, 160), judged,
                   round(judged * ot), round(r.uniform(6, 15), 1), round(lines * r.uniform(0.05, 0.4)), round(lines * r.uniform(0.01, 0.05)),
                   round(lines * r.uniform(0, 0.02)), r.randint(0, 8), iso(today - dt.timedelta(days=r.randint(1, 4))), r.randint(90, 124) if team else r.randint(40, 120)])
    # branch POs by writer: each branch leans on the corporate team to a different degree
    BP, NSI, SBB = [], [], []
    by_size = sorted(sups, key=lambda x: -x["size"])
    home = {x["id"]: r.randrange(4) for x in sups}
    zone = {l[0]: min(3, i * 4 // len(branches)) for i, l in enumerate(branches)}
    buys_at = {l[0]: [x for k, x in enumerate(by_size) if (r.random() < 0.93 if k < 35 else r.random() < (0.55 if home[x["id"]] == zone[l[0]] else 0.04))] for l in branches}
    for l in branches:
        corp_share = r.uniform(0.15, 0.85)
        ns_lean = r.uniform(0.15, 0.5)                      # how much of this branch's buying is non-stock
        total = round(r.uniform(1500, 6500) * l[3])
        writers = [(n, True) for n in r.sample(TEAM, r.randint(2, 4))] + [(branch_buyer[l[0]], False)] + [(person(), False) for _ in range(r.randint(0, 2))]
        cw = [w for w in writers if w[1]]; bw = [w for w in writers if not w[1]]
        for n, is_corp in writers:
            pool = cw if is_corp else bw
            share = (corp_share if is_corp else 1 - corp_share) / len(pool) * r.uniform(0.6, 1.4)
            lines = max(3, round(total * share)); pos = max(1, round(lines / r.uniform(1.6, 4.2))); judged = round(lines * 0.92)
            val = round(lines * r.uniform(350, 900), 2)
            # stocked or not when bought: branch staff lean further into non-stock than the corporate team
            ns = min(0.9, ns_lean * (0.4 if is_corp else 1.6) * r.uniform(0.8, 1.2))
            nsl = round(lines * ns); stl = lines - nsl
            cl = round(nsl * r.uniform(0.35, 0.55)); nl = round(nsl * r.uniform(0.02, 0.08)); dl = nsl - cl - nl
            vs = lambda k: round(val * k / lines, 2) if lines else 0
            pool_s = buys_at[l[0]] or by_size[:10]
            wts = [x["size"] * (3 if k < 35 else 1) for k, x in enumerate(pool_s)]
            tw = sum(wts)
            for x, w in zip(pool_s, wts):
                sl = round(lines * w / tw * r.uniform(0.6, 1.4))
                if sl <= 0:
                    continue
                sj = round(sl * 0.92)
                SBB.append([x["id"], x["name"], l[0], n, x["buyer"], max(1, round(sl / r.uniform(1.6, 4.2))), sl, round(val * w / tw, 2), sj, round(sj * x["ontime"])])
            BP.append([l[0], n, pos, lines, val, round(lines * (0.85 if is_corp else 0.35)), 0 if is_corp else round(lines * r.uniform(0.05, 0.3)),
                       judged, round(judged * r.uniform(0.6, 0.85)), stl, vs(stl), cl, vs(cl), dl, vs(dl), nl, vs(nl),
                       round(nsl * r.uniform(0.03, 0.1)), vs(round(nsl * 0.06)), round(stl * r.uniform(0.01, 0.03)), vs(round(stl * 0.02))])
        for it in r.sample(items, min(len(items), r.randint(40, 90))):
            pos = r.choice([1, 1, 1, 2, 2, 3, 4, 6]); lines = pos + r.randint(0, 2)
            why = r.choices(["c", "d", "n", "m"], [0.4, 0.45, 0.05, 0.1])[0]
            cl = lines if why == "c" else (lines // 2 if why == "m" else 0); nl = lines if why == "n" else 0; dl = lines - cl - nl
            v = round(it["cost"] * r.randint(2, 40) * lines, 2); sold = 0 if why == "n" else r.randint(1, 30)
            NSI.append([l[0], it["id"], it["desc"], lines, pos, v, r.randint(2, 40) * lines, cl, dl, nl, v if why == "n" else 0, r.randint(1, 2),
                        r.choice(writers)[0], iso(today - dt.timedelta(days=r.randint(1, 170))), 1 if r.random() < 0.08 else 0, sold, max(1, sold // 3) if sold else 0])
    mod("branch_purchasing", ["location_id", "buyer", "pos", "po_lines", "po_value", "stock_lines", "direct_lines", "lines_judged", "lines_on_time",
                              "stk_then_lines", "stk_then_val", "ns_cust_lines", "ns_cust_val", "ns_demand_lines", "ns_demand_val", "ns_shelf_lines", "ns_shelf_val",
                              "became_stk_lines", "became_stk_val", "dropped_stk_lines", "dropped_stk_val"], BP)
    # 12 months by supplier, location and writer, with what makes a vendor easy to auto-buy
    AB = []
    sprof = {x["id"]: {"m": r.choices([1197, 708, 300, 2597], [0.8, 0.08, 0.1, 0.02])[0], "fr": r.random() < 0.55, "stk": r.uniform(0.2, 0.95),
                       "ord": r.uniform(0.02, 0.6), "chg": r.uniform(0.005, 0.07)} for x in sups}
    for sid, sname, loc, n, sb, pos, sl, sv, sj, sot in SBB:
        pf, LL = sprof[sid], sl * 2
        fr = r.choice([500, 750, 1000, 1500, 2500]) if pf["fr"] and r.random() < 0.9 else 0
        ln = round(LL * 0.9); lead = r.uniform(4, 18)
        AB.append([sid, sname, loc, n, sb, pos * 2, LL, round(sv * 2, 2), round(LL * r.uniform(0, 0.03)), round(LL * pf["stk"]), round(LL * pf["ord"]),
                   round(LL * r.uniform(0.3, 0.9)), round(LL * pf["chg"]), round(LL * r.uniform(0, 0.01)), round(LL * 0.92), round(LL * 0.92 * r.uniform(0.55, 0.9)),
                   ln, round(ln * lead), round(ln * (lead * lead + (lead * r.uniform(0.15, 0.7)) ** 2)), "DOLLARS", fr, "DOLLARS", r.choice([0, 0, 0, 250, 500]),
                   r.choice([7, 14, 14, 21]), None, None, None, pf["m"], 0])
    mod("autobuy_vendors", ["supplier_id", "supplier_name", "location_id", "buyer", "supplier_buyer", "pos", "po_lines", "po_value", "lines_canceled", "stock_lines",
                            "order_lines", "price_edits", "qty_changes", "expedites", "lines_judged", "lines_on_time", "lead_n", "lead_sum", "lead_sumsq",
                            "freight_control", "freight_target", "min_control", "min_target", "review_cycle", "edi_po", "email_po", "fax_po", "po_method", "min_po_cost"], AB)
    mod("supplier_branch_buying", ["supplier_id", "supplier_name", "location_id", "buyer", "supplier_buyer", "pos", "po_lines", "po_value", "lines_judged", "lines_on_time"], SBB)
    mod("branch_nonstock_items", ["location_id", "item_id", "item_desc", "po_lines", "pos", "po_value", "qty", "cust_lines", "demand_lines", "no_demand_lines",
                                  "no_demand_value", "buyers", "last_buyer", "last_po_date", "stocked_now", "sold_lines_180d", "customers_180d"], NSI)
    mod("buyer_activity", ["buyer", "pos", "po_lines", "lines_canceled", "po_value", "suppliers", "locations", "stock_lines", "direct_pos", "lines_judged",
                           "lines_on_time", "avg_lead_days", "price_overrides", "qty_changed_lines", "expedited_lines", "keyed_by_other", "last_po_date",
                           "days_with_pos"], BA)

    # usage trend (24 months, company-wide)
    UT = []
    months = []
    m0 = dt.date(today.year, today.month, 1)
    for i in range(24, 0, -1):
        y, mth = m0.year, m0.month - i
        while mth <= 0:
            mth += 12; y -= 1
        months.append((y, mth))
    item_d = {}
    for il in IL:
        item_d[il["it"]["id"]] = item_d.get(il["it"]["id"], 0) + il["d"]
    for it in items:
        dd = item_d.get(it["id"], 0)
        if dd <= 0 and r.random() < 0.7:
            continue
        g = it["sup"]["growth"]
        parts = []
        for j, (y, mth) in enumerate(months):
            lvl = (dd or 0.4) * (1 - g * (23 - j) / 12) * (1 + 0.14 * math.sin(2 * math.pi * (mth - 3) / 12))
            q = max(0, round(lvl * r.lognormvariate(0, 0.45))) if r.random() > 0.08 else 0
            if q:
                parts.append(f"{y}{mth:02d}:{q:.2f}")
        if parts:
            UT.append([it["id"], ",".join(parts)])
    mod("usage_trend", ["item_id", "months"], UT)

    # supplier performance, supplier fill, vendor growth
    SP, SF, VG = [], [], []
    rec_val = {}
    for x in RD:
        rec_val[x[3]] = rec_val.get(x[3], 0) + x[7]
    loc_lines = {}
    for il in IL:
        if il["type"] in ("BRANCH", "CORP") and il["stocked"]:
            k_ = (il["it"]["sup"]["id"], il["loc"])
            loc_lines[k_] = loc_lines.get(k_, 0) + max(1, round(il["d"] / max(1, il["max"] - il["min"]) * 6 + r.uniform(0, 2)))
    for s in sups:
        val12 = rec_val.get(s["id"], 0) * 365 / 70
        lines = max(1, round(val12 / r.uniform(260, 900)))
        if val12 <= 0:
            continue
        SP.append([s["id"], s["name"], s["buyer"], lines, round(s["lead"] * r.uniform(1.05, 1.3), 1), s["lead"], round(s["ontime"], 4),
                   round(s["fill"], 4), round(val12, 2), s["ret_days"], s["restock"], s["policy"]])
        for (sid_, lid), n in loc_lines.items():
            if sid_ != s["id"]:
                continue
            ff = round(n * min(1, s["fill"] + r.uniform(-0.04, 0.01)))
            ot = round(n * min(1, s["ontime"] + r.gauss(0, 0.04)))
            otif = min(ot, ff, round(n * s["ontime"] * s["fill"]))
            nr = round(n * r.uniform(0, 0.06))
            qo = round(n * r.uniform(8, 60))
            pos = max(1, round(n / r.uniform(2, 4.5)))
            SF.append([s["id"], s["name"], lid, s["buyer"], n, ff, ot, otif, nr, qo, round(qo * (otif / n) * r.uniform(0.95, 1.05)),
                       round(qo * r.uniform(4, 40), 2), round(r.uniform(2, 13), 1) if ot < n else None, pos, round(pos * r.uniform(0.55, 0.85))])
    mod("supplier_perf", ["supplier_id", "supplier_name", "supplier_buyer", "lines_received", "avg_lead_days", "median_lead_days", "on_time_rate",
                          "fill_rate", "value_received", "return_days", "restock_rate", "return_policy"], SP)
    mod("supplier_fill", ["supplier_id", "supplier_name", "location_id", "supplier_buyer", "lines", "lines_full_first", "lines_on_time", "lines_otif",
                          "lines_not_received", "qty_ordered", "qty_by_due", "value_ordered", "avg_days_late", "pos", "pos_one_receipt"], SF)
    sup_cogs_ratio = {}
    for it in items:
        sup_cogs_ratio.setdefault(it["sup"]["id"], []).append(1 / it["markup"])
    vstart = dt.date(m0.year - 2, m0.month, 1)
    for s in sups:
        s12 = sup_sales.get(s["id"], 0)
        if s12 <= 0:
            continue
        cr = sum(sup_cogs_ratio[s["id"]]) / len(sup_cogs_ratio[s["id"]])
        g = s["growth"]
        lv = [(1 + g) ** ((j - 18) / 12) * (1 + 0.12 * math.sin(2 * math.pi * (((vstart.month + j - 1) % 12) + 1 - 3) / 12)) for j in range(25)]
        norm = s12 / sum(lv[12:24])
        for j in range(25):
            y, mth = vstart.year + (vstart.month - 1 + j) // 12, (vstart.month - 1 + j) % 12 + 1
            mtd = j == 24
            frac = (today.day / 30.4) if mtd else 1
            sales = lv[j] * norm * r.uniform(0.9, 1.1) * frac
            cogs = sales * cr * r.uniform(0.97, 1.03)
            purch = cogs * r.uniform(0.82, 1.2)
            VG.append([s["id"], s["name"], iso(dt.date(y, mth, 1)), round(purch, 2), max(1, round(purch / r.uniform(1800, 4200))), round(sales, 2), round(cogs, 2)])
    mod("vendor_growth", ["supplier_id", "supplier_name", "month", "purchases", "receipts", "sales", "cogs"], VG)

    sets = {
        "A": {"columns": ["location_id", "location_name", "loc_type", "item_id", "description", "product_group", "abc_class", "supplier_id",
                          "supplier_name", "stockable", "qty_remaining", "cost_on_hand", "replacement_cost", "inv_max", "most_recent_receipt_date",
                          "most_recent_sale_date", "most_recent_purchase_date", "days_since_recent_receipt", "days_since_recent_sale",
                          "days_since_recent_purchase", "oldest_open_layer_date", "max_days_since_received_layer", "older_layer_count",
                          "qty_in_older_layers", "cost_in_older_layers", "status_rank", "inv_status", "total_usage", "avg_monthly_usage",
                          "days_on_hand", "last_buyer", "last_buyer_dept", "last_po_no"], "rows": A},
        "C": {"columns": ["supplier_id", "supplier_name", "fifo_layer_no", "date_received", "days_since_received_layer", "fifo_layer_cost",
                          "replacement_cost", "qty_received", "qty_remaining", "cost_on_hand", "location_id", "location_name", "loc_type", "item_id",
                          "description", "abc_class", "last_sale_date", "last_purchase_date", "product_group", "stockable", "inv_max", "journal",
                          "po_no", "requested_by_name", "buyer", "origin_source", "requester_dept", "most_recent_receipt_date", "_dsr",
                          "most_recent_sale_date", "_dss", "most_recent_purchase_date", "_dsp", "is_older_open_layer", "inv_status",
                          "status_rank", "rn_pg_topN", "rn_overall"], "rows": C},
        "K": {"columns": ["item_id", "location_id", "total_usage"], "rows": K},
        "L": {"columns": ["run_date", "usage_window_start", "usage_window_end", "work_days", "usage_months", "company_id", "dead_days",
                          "slow_days", "aging_days"], "rows": L},
        "M": {"columns": ["location_id", "item_id", "buyer", "requester_dept", "origin_source", "layer_count", "po_count", "latest_po_no",
                          "qty_remaining", "cost_on_hand", "first_received", "last_received"], "rows": M},
        "_modules": mods,
    }
    run_info = dict(zip(sets["L"]["columns"], L[0]))
    payload = {
        "app": {"title": "Inventory Health", "tagline": "Purchasing analytics", "corp_buyers": [t.split()[-1].upper() for t in TEAM],
                "feedback_email": FEEDBACK},
        "generated_at": dt.datetime.combine(today, dt.time(5, 12, 7)).isoformat(timespec="seconds"),
        "source": SOURCE, "query_seconds": 71.4, "params": params, "run_info": run_info,
        "locations": [{"location_id": l[0], "location_name": l[1], "loc_type": l[2]} for l in LOCS],
        "items": sets["A"], "top_layers": sets["C"], "usage": sets["K"], "buyers": sets["M"], "modules": mods,
    }

    # history snapshots: 12 weekly, following each location's value path
    hist = []
    snap = {}
    for row in A:
        key = (row[0], row[26])
        a = snap.setdefault(key, {"location_id": str(row[0]), "location_name": row[1], "loc_type": row[2], "inv_status": row[26],
                                  "item_count": 0, "qty_remaining": 0.0, "cost_on_hand": 0.0})
        a["item_count"] += 1; a["qty_remaining"] += row[10]; a["cost_on_hand"] += row[11]
    for w in range(12, -1, -1):
        d = today - dt.timedelta(weeks=w)
        for (lid, st), a in snap.items():
            path = hist_path.get(lid, {})
            wk = monday - dt.timedelta(weeks=w)
            ratio = (path.get(wk, rows_by_loc.get(lid, 1)) / max(1, rows_by_loc.get(lid, 1))) if w else 1
            if st in ("DEAD", "SLOW"):
                ratio *= 1 - 0.006 * w
            hist.append({"snapshot_date": d.isoformat(), **a, "item_count": max(1, round(a["item_count"] * (ratio if w else 1))),
                         "qty_remaining": round(a["qty_remaining"] * ratio, 4), "cost_on_hand": round(a["cost_on_hand"] * ratio, 2)})
    # weekly backfill from January 1 to the first saved snapshot (module status_history), same value path
    SH = []
    first_snap = today - dt.timedelta(weeks=12)
    d = dt.date(today.year, 1, 1)
    while d < first_snap:
        wk = d - dt.timedelta(days=d.weekday())
        for (lid, st), a in snap.items():
            path = hist_path.get(lid, {})
            ratio = path.get(wk, rows_by_loc.get(lid, 1)) / max(1, rows_by_loc.get(lid, 1))
            w = (first_snap - d).days / 7 + 12
            if st in ("DEAD", "SLOW"):
                ratio *= 1 - 0.006 * w
            SH.append([iso(d), lid, st if st not in ("CORP", "CONSIGNMENT") else "ACTIVE", max(1, round(a["item_count"] * ratio)),
                       round(a["qty_remaining"] * ratio, 4), round(a["cost_on_hand"] * ratio, 2)])
        d += dt.timedelta(days=7)
    mod("status_history", ["snapshot_date", "location_id", "inv_status", "item_count", "qty_remaining", "cost_on_hand"], SH)
    big = sorted(sup_sales.items(), key=lambda x: -x[1])[:6]
    names = {s["id"]: s["name"] for s in sups}
    terms = {}
    for i, (sid_, v) in enumerate(big[:4]):
        terms[str(sid_)] = {"rebate_pct": [2, 1.5, 3, 1][i], "rebate_basis": ["Purchases over threshold", "All purchases", "Growth over prior year", "All purchases"][i],
                            "rebate_threshold": [500000, None, None, 250000][i], "rebate_period": "Annual", "payment_terms": ["2% 10 net 30", "Net 45", "1% 15 net 30", "Net 30"][i],
                            "freight_terms": ["Prepaid at $1,500", "Prepaid at $2,500", "FOB origin", "Prepaid at $1,000"][i],
                            "supplier_name": names[sid_], "updated": dt.datetime.combine(today - dt.timedelta(days=20 + i * 9), dt.time(10, 30)).isoformat(timespec="seconds"),
                            "updated_by": "dwhitfield"}
        terms[str(sid_)] = {k_: v_ for k_, v_ in terms[str(sid_)].items() if v_ is not None}
    return sets, payload, hist, terms


# ---- overlap check against the live cache ----
NAME_COLS = {"item_id", "description", "item_desc", "supplier_name", "product_group", "location_name", "last_buyer", "buyer",
             "requested_by_name", "supplier_buyer", "primary_buyer", "po_buyer", "changed_by", "last_customer_name",
             "top_customer_12m_name", "return_policy"}
ID_COLS = {"supplier_id", "primary_supplier_id", "location_id", "last_customer_id", "top_customer_12m_id", "po_no", "receipt_no",
           "latest_po_no", "last_po_no", "open_po_no", "next_po_no", "fifo_layer_no", "sales_order_number", "top_customer_12m_location"}
GENERIC = {None, "", BRANCH_SPEC, "No buyer assigned", "(Non-PO: TR)", "(Non-PO: IA)", "(no product group)"}


def _collect(payload):
    names, ids = set(), set()
    tables = [payload["items"], payload["top_layers"], payload["usage"], payload["buyers"]] + list(payload["modules"].values())
    for t in tables:
        if not t or "columns" not in t:
            continue
        for ci, c in enumerate(t["columns"]):
            if c in NAME_COLS:
                names.update(str(row[ci]).strip().upper() for row in t["rows"] if row[ci] not in GENERIC)
            elif c in ID_COLS:
                ids.update(str(row[ci]) for row in t["rows"] if row[ci] is not None)
    for l in payload["locations"]:
        names.add(l["location_name"].upper()); ids.add(str(l["location_id"]))
    return names, ids


def overlap(payload, live_paths=None):
    live_paths = live_paths or [ROOT / "data" / "latest.json", ROOT / "data_ieg" / "latest.json"]
    dn, di = _collect(payload)
    words = {w for n in dn for w in n.replace(",", " ").split() if len(w) > 3}
    bad = {}
    for p in live_paths:
        if not p.exists():
            continue
        ln, li = _collect(json.loads(p.read_text(encoding="utf-8")))
        cities = {l["location_name"].upper() for l in json.loads(p.read_text(encoding="utf-8"))["locations"]}
        city_words = {w for c in cities for w in c.split() if w not in ("CORP", "CONSIGNMENT", "SAN", "SANTA")}
        bad[p.parent.name] = {"names": sorted(dn & ln)[:20], "n_names": len(dn & ln), "ids": sorted(di & li)[:20], "n_ids": len(di & li),
                              "city_words": sorted(words & city_words)}
    return bad


def write(out_dir: Path = DEMO_DIR, today=None, workbook=True):
    sets, payload, hist, terms = build(today)
    out_dir.mkdir(exist_ok=True)
    tmp = out_dir / "latest.tmp"
    tmp.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
    tmp.replace(out_dir / "latest.json")
    with (out_dir / "history.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["snapshot_date", "location_id", "location_name", "loc_type", "inv_status", "item_count",
                                          "qty_remaining", "cost_on_hand"])
        w.writeheader(); w.writerows(hist)
    (out_dir / "vendor_terms.json").write_text(json.dumps(terms, indent=1), encoding="utf-8")
    def wb():
        try:
            sys.path.insert(0, str(ROOT))
            from inventory_app import write_workbook
            write_workbook(sets, out_dir / "latest.xlsx")
        except Exception as ex:   # the dashboard works without the workbook
            print(f"Could not write sample workbook: {ex}")
    if workbook == "background":
        import threading
        threading.Thread(target=wb, daemon=True).start()
    elif workbook:
        wb()
    return payload


if __name__ == "__main__":
    if "--check" in sys.argv:
        _, p, _, _ = build()
    else:
        p = write()
        print(f"Wrote {DEMO_DIR}")
    m = p["modules"]
    print("item-locations", len(p["items"]["rows"]), "| inventory $%.1fM" % (sum(r[11] for r in p["items"]["rows"]) / 1e6),
          "| sales 12m $%.1fM" % (sum(r[3] for r in m["sales_12m"]["rows"]) / 1e6), "| stockouts", len(m["stockout_events"]["rows"]),
          "| fill lines", sum(r[3] for r in m["fill_rate"]["rows"]))
    print(json.dumps(overlap(p), indent=1))
