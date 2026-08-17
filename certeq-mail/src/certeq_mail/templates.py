"""The eight KVS1 emails, ported 1:1 from KVS1_2026.bas.

Each builder returns (subject, to, cc, html, wants_signature). Body text and
recipient lists are kept identical to the VBA originals.
"""

from datetime import datetime

FONT = '<font face="Calibri" size="2" color="black">'
FONT_LARGE = '<font face="Calibri" size="4" color="black">'

TD = '<td style="padding-left:10px;">'
CELL_STYLE = (
    "border-color:#5b9bd5;border-left-style:solid;border-width:1px;"
    "padding-left:10px;padding-right:10px"
)


def _details_table(pairs: list[tuple[str, str]]) -> str:
    body = "".join(f"<tr><td>{label}</td>{TD}{value}</td></tr>" for label, value in pairs)
    return f"<br><br><ul><table>{FONT}{body}</table></ul>"


def soe_recovery(row: dict, market: str) -> tuple:
    """SOE_AU_Recovery / SOE_NZ_Recovery (queries 220 / 3613)."""
    store_id, store_name = row["Store"], row["Store Name"]
    html = FONT + "Hi Level 2,"
    html += (
        f"<br><br>We have just installed a VM SOE at <b>{store_id} - {store_name}</b>, "
        "could you please kick off the SOE recovery file distribution job with the "
        "following details:"
    )
    html += _details_table([
        ("Market:", market),
        ("Site ID:", store_id),
        ("Site Name:", store_name),
        ("SOE IP:", f"{row['IP']}.1"),
        ("State", row["State"]),
        ("Status", row["Status"]),
    ])
    if market == "NZ":
        html += "<br>"
        cc = "sme@certeq.com.au;caleb.archer@nz.mcd.com"
    else:
        cc = (
            "mcd@certeq.com.au;karthick.raghuraman@au.mcd.com;"
            "Malcolm.Little@au.mcd.com;jason.conevski@au.mcd.com"
        )
    return (
        f"SOE VM Recovery: {store_id} - {store_name}",
        "IT.RestaurantSupport@au.mcd.com",
        cc,
        html,
        True,
    )


def dmaas(row: dict, market: str) -> tuple:
    """DMAAS_AU / DMAAS_NZ (queries 1320 / 3609)."""
    store_id, store_name = row["Store"], row["Store Name"]
    state, lan = row["State"], row["Network_LanAddress"]
    prefix = f"{market}0{store_id}"
    country = "Australia" if market == "AU" else "New Zealand"
    go_live = datetime.now().strftime("%a, %d-%b-%y")

    html = FONT
    html += "<b>Service Café Ticket Mapping (Country code in format AU or NZ)</b>"
    html += f"<br>Site ID: {store_id}"
    html += f"<br>Country Code: {market}"
    html += "<br><br><b>The following store has been staged:</b>"
    html += f"<br>McD {store_id} {store_name} {state} {country}"
    html += (
        "<br><br><b>ACTION REQUIRED:</b> DMaaS L3 / RSM L3 / McD Level 2 - This "
        "request has been created for your action. Ensure you have completed your "
        "relevant tasks below before closing this request!"
    )
    html += "<br><br><b><u>IP Addresses</u></b><ul>"
    html += f"<li>{prefix}SOE01 - {lan}.1</li>"
    html += f"<li>{prefix}GSC01 - {lan}.124</li>"
    html += f"<li>{prefix}GSC02 - {lan}.123</li>"
    html += f"<li>{prefix}RHS01 - {lan}.94</li>"
    html += f"<li>{prefix}RHS02 - {lan}.93</li>"
    html += "</ul><b><u>Remote Management Interface Details</u></b><ul>"
    html += f"<li>{prefix}RHS01 - {row['RHS01 MAC']}</li>"
    html += f"<li>{prefix}RHS02 - {row['RHS02 MAC']}</li>"
    html += "</ul><b><u>DMaaS L3 GLOBAL Support Team:</u></b><ul>"
    html += "<li>Provision restaurant in DMaaS</li>"
    html += "<li>Test DMaaS connectivity from the DMaaS Servers to the Waystation DMaaS client</li>"
    html += "<li>Once validated, please advise the McDonald's RFM Team so they can test RFM package delivery </li>"
    html += "</ul><b><u>McD IT Foundation Team:</u></b><ul>"
    html += "<li>Check all switch interconnections are working as required</li>"
    html += "</ul><b><u>McD L2 Team:</u></b><ul>"
    html += (
        "<li>Ensure the correct groups are applied to the SOE in Resilio. "
        "(State group for the restaurant's location should be added as a minimum)</li>"
    )
    html += (
        '<li>Update "Restaurant Connectivity Configurator" to update RDCMan (*.rdg) '
        "file with Waystation and Production Host Names (GSC01/GSC02)</li>"
    )
    html += "<li>Run Apps to SOE Recovery Job (1 hour process)</li>"
    html += "<li>Validate POSConnector is running on Waystation after Apps to SOE Recovery Job</li>"
    html += "<li>Escalate to MFM/RFM for completion of their tasks</li>"
    html += "</ul><b><u>RFM Team:</u></b><ul>"
    html += "<li>Please Update/Confirm RFM to ensure KS Groups align with KVS1 requirements</li>"
    html += "<li>The restaurant has a Delivery <u>KVS</u>: Yes</li>"
    html += "<li>The restaurant has a Delivery <u>POS</u>: Yes</li>"
    html += "<li>The restaurant has a Delivery <u>ORB</u>: Yes</li>"
    html += "<li>The restaurant has a Hub and Spoke: Yes</li>"
    html += "</ul><b><u>Capgemini Service Desk:</u></b><ul>"
    html += (
        "<li>This store is on NextGen Back-Office Platform, Test RDP &amp; UltraVNC "
        "connectivity to the Back-Office SOE PC and relevant devices</li>"
    )
    html += "<li>Communicate this restaurant is now on KVS1</li>"
    html += f"</ul>{FONT_LARGE}<b>This store's Go Live date is:  {go_live}</b><br><br>{FONT}"

    to = (
        "servicecafe@service-now.com;cfm@au.mcd.com;"
        "anzsupportleads1.5.in@capgemini.com;aus-it-networkteam@au.mcd.com;"
        "US-DL_DMaaS_Operations@us.mcd.com;US-DL_RTPaaS_RSM_L3_Service@us.mcd.com"
    )
    if market == "AU":
        cc = (
            "mcd@certeq.com.au;Malcolm.Little@au.mcd.com;McD_IT_Deploy@au.mcd.com;"
            "aurtpteam@au.mcd.com;Troy.Urquhart@certeq.com.au;"
            "daniel.phillips@certeq.com.au;nic.henstridge@certeq.com.au;"
            "dave.hawtin@certeq.com.au"
        )
    else:
        cc = (
            "sme@certeq.com.au;McD_IT_Deploy@au.mcd.com;aurtpteam@au.mcd.com;"
            "caleb.archer@nz.mcd.com"
        )
    return (
        f"DMaaS / RSM / McD - {store_id} {store_name} {state} {row['Owner']} ({country})",
        to,
        cc,
        html,
        False,
    )


def maxtel_recovery(row: dict) -> tuple:
    """Maxtel_Recovery (query 3613)."""
    store_id, store_name = row["Store"], row["Store Name"]
    html = FONT + "Hi Maxtel Team,"
    html += f"<br><br>We have just installed a VM SOE at <b>{store_id} - {store_name}</b>."
    html += "<br><br>Can you please confirm that you are receiving all appropriate files post this upgrade."
    html += "<br><br>The VM SOE has been configured with the following details:"
    html += _details_table([
        ("Market:", "NZ"),
        ("Site ID:", store_id),
        ("Site Name:", store_name),
        ("SOE IP:", f"{row['IP']}.1"),
    ])
    html += "<br>"
    return (
        f"NZ{store_id} -{store_name} | VM SOE Upgrade | Maxtel Checks",
        "support@maxtel.com",
        "sme@certeq.com.au;caleb.archer@nz.mcd.com;steven.fox@maxtel.com;"
        "james.diamond-jennings@maxtel.com",
        html,
        True,
    )


ISSUES_LIST = (
    '<ul><li><b>Issue Description</b> | Status: <b><font color="red">OPEN</font></b> (Certeq - to resolve)</li>'
    '<li><b>Issue Description</b> | Status: <b><font color="red">OPEN</font></b> (Resturant - to resolve)</li>'
    '<li><b>Issue Description</b> | Status: <b><font color="red">ESCALATED</font></b> (Certeq L2)</li>'
    '<li><b>Issue Description</b> | Status: <b><font color="red">ESCALATED</font></b> (McD L2)</li>'
    '<li><b>Issue Description</b> | Status: <b><font color="red">ESCALATED</font></b> (Maxtel)</li>'
    '<li><b>Issue Description</b> | Status: <b><font color="red">ESCALATED</font></b> (Seaseme)</li>'
    '<li><b>Issue Description</b> | Status: <b><font color="red">ESCALATED</font></b> (RTP)</li>'
    '<li><b>Issue Description</b> | Status: <b><font color="green">RESOLVED</font></b></li></ul>'
)


def _qr_block(whatsapp_url: str) -> str:
    qr = f"https://api.qrserver.com/v1/create-qr-code/?data={whatsapp_url}&size=150x150"
    return (
        f'<br><img src="{qr}">'
        "<br><br><i>Note: You may need to click the email popup 'Click here to "
        "download pictures. To help protect your privacy, Outlook prevented "
        "automatic download of some pictures in this message.' to display the QR "
        "Code.</i><br><br>URL:"
        f'<br><a href="{whatsapp_url}" target="_blank">{whatsapp_url}</a></ul>'
    )


MAXTEL_SALES_BLOCK = (
    "<br><b>Maxtel Sales Data:</b>"
    "<ul><br>Please note that because of the change to the Virtual SOE Maxtel is "
    "required to manually log on and install OnTarget."
    "<br><br>Sales data will start flowing through to Maxtel Web after a few hours."
    "<br><br>If it reaches midday and you are still having issues with sales data "
    "to either Maxtel Web or OnTarget please reach out to Certeq via the "
    "Hyper-Support Chat.</ul>"
)


def _after_hours_block(email: str) -> str:
    return (
        "<br>If you have any urgent issues that are impacting trade please contact "
        "our After Hours Support via:"
        "<br><br><ul>Certeq Project Team"
        f'<br><a href="mailto:{email}">{email}</a>'
        '<br>Phone: <a href="tel:+61448003441">+61 448 003 441</a></ul>'
    )


FEEDBACK_LINE = (
    "If you would like to provide us with some feedback on this installation, this "
    'can be completed via: <a href="https://feedback.certeq.com.au">feedback.certeq.com.au</a>'
)


def kvs1_nz_completion(row: dict) -> tuple:
    """KVS1_NZ_Completion (query 3612)."""
    html = FONT + "Hi Restaurant Manager,"
    html += (
        "<br><br>Certeq has now completed the <b>KVS1 Conversion</b> at your "
        f"<b>{row['Site_Name']}</b> restaurant."
    )
    html += (
        "<br><br>We will be running our Hyper Support through WhatsApp until "
        f"<b>{row['support_date']}</b>. If you could please ensure your team raises "
        "any faults by replying to this email or via the WhatsApp Chat:"
    )
    html += "<br><br>QR Code:"
    html += _qr_block(row["whatsapp_hypersupport"])
    html += MAXTEL_SALES_BLOCK
    html += _after_hours_block("mcd@certeq.co.nz")
    html += "<br><br>" + FEEDBACK_LINE
    html += "<br><br>"
    return (
        f"[Post Deployment Support] Ref ID: {row['Ref_ID']} | "
        f"KVS1 Conversion: {row['Site_ID']} - {row['Site_Name']}",
        row["email_dl"],
        row["email_cc"],
        html,
        True,
    )


def kvs_nz_completion_issues(row: dict) -> tuple:
    """KVS_NZ_Completion_Issues (query 3612)."""
    html = FONT + "Hi Restaurant Manager,"
    html += (
        "<br><br>Certeq has now completed the <b>KVS1 Conversion</b> at your "
        f"<b>{row['Site_Name']}</b> restaurant."
    )
    html += "<br><br>During the conversion the following issues that arose that we still need to close out:"
    html += ISSUES_LIST
    html += (
        "We will be running our Hyper Support through WhatsApp until "
        f"<b>{row['support_date']}</b>. If you could please ensure your team raises "
        "any faults by replying to this email or via the WhatsApp Chat:"
    )
    html += "<br><br><ul>QR Code:"
    html += _qr_block(row["whatsapp_hypersupport"])
    html += MAXTEL_SALES_BLOCK
    html += _after_hours_block("mcd@certeq.co.nz")
    html += "<br>" + FEEDBACK_LINE
    html += "<br>"
    return (
        f"[Post Deployment Support] Ref ID: {row['Ref_ID']} | "
        f"KVS1 Conversion: {row['Site_ID']} - {row['Site_Name']}",
        row["email_dl"],
        row["email_cc"],
        html,
        True,
    )


def kvs_nz_completion_issues_update(row: dict) -> tuple:
    """KVS_NZ_Completion_Issues_Update (query 3612)."""
    wa = row["whatsapp_hypersupport"]
    html = FONT + "Hi Restaurant Manager,"
    html += (
        "<br><br>An update on the issues from <b>KVS1 Conversion</b> at your "
        f"<b>{row['Site_Name']}</b> restaurant:"
    )
    html += ISSUES_LIST
    html += (
        "If you are still seeing issues outside of the above list please reply to "
        "this email or respond to us via WhatsApp: "
        f'<a href="{wa}" target="_blank">{wa}</a>'
    )
    html += "<br>" + _after_hours_block("mcd@certeq.com.au")
    html += "<br>" + FEEDBACK_LINE
    html += "<br><br>"
    return (
        f"[Post Deployment Support - Update] Ref ID: {row['Ref_ID']} | "
        f"KVS1 Conversion: {row['Site_ID']} - {row['Site_Name']}",
        row["email_dl"],
        row["email_cc"],
        html,
        True,
    )


def daily_report(report_rows: list[dict]) -> tuple:
    """KVS1NZ_Daily_Report (query 3614)."""
    columns = ["ID", "Site Name", "Install Date", "Status", "Authority to Open given"]
    table = f"<table>{FONT}<tr>"
    table += "".join(
        f'<th style="padding-left:10px;padding-right:10px" align="left">{c}</th>'
        for c in columns
    )
    table += "</tr>"
    for row in report_rows:
        table += "<tr>"
        table += "".join(
            f'<td style="{CELL_STYLE}"> {row.get(c, "")} </td>' for c in columns
        )
        table += "</tr>"
    table += "</table>"

    html = FONT + "Hi Team,"
    html += "<br><br>Please see the report for last nights KVS1 conversions:"
    html += f"<br><br><ul>{table}</ul>"
    html += "<br><br><b>Conversion Notable Items:</b>"
    html += "<br><br><b>Lessons Learnt:</b><br><br>"
    return (
        "KVS1 Conversions Report (NZ & PI): " + datetime.now().strftime("%A, %d-%b-%y"),
        "caleb.archer@nz.mcd.com;david.moors@nz.mcd.com;brook.dando@nz.mcd.com;"
        "jonathan.wong@nz.mcd.com",
        "sme@certeq.com.au;mcd@certeq.co.nz;aus-it-networkteam@au.mcd.com;"
        "it.restaurantsupport@au.mcd.com;aurtpteam@mcdonaldscorp.onmicrosoft.com",
        html,
        True,
    )
