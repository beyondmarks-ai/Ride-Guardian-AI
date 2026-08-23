from pathlib import Path

from PIL import Image as PILImage
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    Image,
    KeepTogether,
    ListFlowable,
    ListItem,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


ROOT = Path(__file__).resolve().parents[1]
IMAGE_DIR = ROOT / "docs" / "images"
OUTPUT_DIR = ROOT / "output" / "pdf"
OUTPUT_FILE = OUTPUT_DIR / "RideGuardian_AI_Client_Overview.pdf"

PAGE_W, PAGE_H = A4
NAVY = colors.HexColor("#0D2722")
GREEN = colors.HexColor("#11836F")
LIME = colors.HexColor("#B8EE7D")
AMBER = colors.HexColor("#F4A62A")
RED = colors.HexColor("#E34C4C")
INK = colors.HexColor("#13211F")
MUTED = colors.HexColor("#60726E")
PALE = colors.HexColor("#F2F6F4")
PALE_GREEN = colors.HexColor("#E7F3EF")
OUTLINE = colors.HexColor("#D6E0DC")
WHITE = colors.white


def register_fonts():
    font_dir = Path("C:/Windows/Fonts")
    pdfmetrics.registerFont(TTFont("Segoe", str(font_dir / "segoeui.ttf")))
    pdfmetrics.registerFont(TTFont("Segoe-Semibold", str(font_dir / "seguisb.ttf")))
    pdfmetrics.registerFont(TTFont("Segoe-Bold", str(font_dir / "segoeuib.ttf")))
    pdfmetrics.registerFontFamily(
        "Segoe",
        normal="Segoe",
        bold="Segoe-Bold",
        italic="Segoe",
        boldItalic="Segoe-Bold",
    )


register_fonts()
BASE = getSampleStyleSheet()
STYLES = {
    "cover_eyebrow": ParagraphStyle(
        "cover_eyebrow",
        fontName="Segoe-Bold",
        fontSize=10,
        leading=13,
        textColor=LIME,
        spaceAfter=10,
        tracking=1.1,
    ),
    "cover_title": ParagraphStyle(
        "cover_title",
        fontName="Segoe-Bold",
        fontSize=34,
        leading=38,
        textColor=WHITE,
        spaceAfter=16,
    ),
    "cover_body": ParagraphStyle(
        "cover_body",
        fontName="Segoe",
        fontSize=13,
        leading=19,
        textColor=colors.HexColor("#D3E0DC"),
        spaceAfter=16,
    ),
    "cover_small": ParagraphStyle(
        "cover_small",
        fontName="Segoe-Semibold",
        fontSize=9,
        leading=13,
        textColor=colors.HexColor("#B6C7C2"),
    ),
    "eyebrow": ParagraphStyle(
        "eyebrow",
        fontName="Segoe-Bold",
        fontSize=9,
        leading=12,
        textColor=GREEN,
        spaceAfter=6,
        tracking=0.8,
    ),
    "title": ParagraphStyle(
        "title",
        fontName="Segoe-Bold",
        fontSize=24,
        leading=29,
        textColor=INK,
        spaceAfter=10,
    ),
    "h2": ParagraphStyle(
        "h2",
        fontName="Segoe-Bold",
        fontSize=15,
        leading=19,
        textColor=INK,
        spaceBefore=8,
        spaceAfter=7,
    ),
    "h3": ParagraphStyle(
        "h3",
        fontName="Segoe-Bold",
        fontSize=11,
        leading=15,
        textColor=INK,
        spaceAfter=4,
    ),
    "body": ParagraphStyle(
        "body",
        fontName="Segoe",
        fontSize=9.6,
        leading=14.2,
        textColor=MUTED,
        spaceAfter=8,
    ),
    "body_dark": ParagraphStyle(
        "body_dark",
        fontName="Segoe",
        fontSize=9.6,
        leading=14.2,
        textColor=INK,
        spaceAfter=7,
    ),
    "small": ParagraphStyle(
        "small",
        fontName="Segoe",
        fontSize=8,
        leading=11,
        textColor=MUTED,
    ),
    "caption": ParagraphStyle(
        "caption",
        fontName="Segoe",
        fontSize=7.7,
        leading=10,
        alignment=TA_CENTER,
        textColor=MUTED,
        spaceBefore=5,
    ),
    "card_title": ParagraphStyle(
        "card_title",
        fontName="Segoe-Bold",
        fontSize=11,
        leading=14,
        textColor=INK,
        spaceAfter=4,
    ),
    "card_body": ParagraphStyle(
        "card_body",
        fontName="Segoe",
        fontSize=8.8,
        leading=12.5,
        textColor=MUTED,
    ),
    "table_head": ParagraphStyle(
        "table_head",
        fontName="Segoe-Bold",
        fontSize=8.2,
        leading=10,
        textColor=WHITE,
    ),
    "table": ParagraphStyle(
        "table",
        fontName="Segoe",
        fontSize=7.5,
        leading=10,
        textColor=INK,
    ),
    "table_bold": ParagraphStyle(
        "table_bold",
        fontName="Segoe-Bold",
        fontSize=7.5,
        leading=10,
        textColor=INK,
    ),
    "center": ParagraphStyle(
        "center",
        fontName="Segoe-Semibold",
        fontSize=9,
        leading=12,
        alignment=TA_CENTER,
        textColor=INK,
    ),
}


def p(text, style="body"):
    return Paragraph(text, STYLES[style])


def bullet_list(items, font_size=9.2):
    style = ParagraphStyle(
        "bullet_body",
        parent=STYLES["body_dark"],
        fontSize=font_size,
        leading=13,
        leftIndent=0,
        spaceAfter=0,
    )
    return ListFlowable(
        [ListItem(Paragraph(item, style), leftIndent=9) for item in items],
        bulletType="bullet",
        bulletFontName="Segoe-Bold",
        bulletFontSize=6,
        bulletColor=GREEN,
        leftIndent=13,
        bulletOffsetY=1,
        spaceBefore=3,
        spaceAfter=6,
    )


def screenshot(name, width=211 * mm):
    path = IMAGE_DIR / name
    with PILImage.open(path) as im:
        ratio = im.height / im.width
    return Image(str(path), width=width, height=width * ratio)


def section_header(number, title, subtitle):
    return [
        p("RIDEGUARDIAN AI  /  %s" % number, "eyebrow"),
        p(title, "title"),
        p(subtitle, "body"),
        Spacer(1, 3 * mm),
    ]


def card(title, body, accent=GREEN):
    data = [[p(title, "card_title")], [p(body, "card_body")]]
    table = Table(data, colWidths=[76 * mm])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), PALE),
                ("BOX", (0, 0), (-1, -1), 0.7, OUTLINE),
                ("LINEBEFORE", (0, 0), (0, -1), 4, accent),
                ("LEFTPADDING", (0, 0), (-1, -1), 12),
                ("RIGHTPADDING", (0, 0), (-1, -1), 12),
                ("TOPPADDING", (0, 0), (-1, 0), 11),
                ("BOTTOMPADDING", (0, -1), (-1, -1), 11),
            ]
        )
    )
    return table


def phone_panel(image_name, caption):
    image = screenshot(image_name, 67 * mm)
    panel = Table(
        [[image], [p(caption, "caption")]],
        colWidths=[74 * mm],
    )
    panel.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), WHITE),
                ("BOX", (0, 0), (-1, -1), 0.8, OUTLINE),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                ("TOPPADDING", (0, 0), (-1, 0), 10),
                ("BOTTOMPADDING", (0, -1), (-1, -1), 9),
            ]
        )
    )
    return panel


def walkthrough_page(story, number, title, subtitle, image_name, caption, content):
    story.append(PageBreak())
    story.extend(section_header(number, title, subtitle))
    left = []
    for item in content:
        if isinstance(item, tuple):
            left.append(p(item[0], item[1]))
        elif isinstance(item, list):
            left.append(bullet_list(item))
        else:
            left.append(item)
    layout = Table(
        [[left, phone_panel(image_name, caption)]],
        colWidths=[100 * mm, 79 * mm],
        hAlign="LEFT",
    )
    layout.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (0, 0), 0),
                ("RIGHTPADDING", (0, 0), (0, 0), 14),
                ("LEFTPADDING", (1, 0), (1, 0), 0),
                ("RIGHTPADDING", (1, 0), (1, 0), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 0),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
            ]
        )
    )
    story.append(layout)


def feature_table(rows):
    data = [
        [
            p("Capability", "table_head"),
            p("Client value", "table_head"),
            p("Implementation", "table_head"),
        ]
    ]
    for capability, value, implementation in rows:
        data.append(
            [
                p(capability, "table_bold"),
                p(value, "table"),
                p(implementation, "table"),
            ]
        )
    table = Table(data, colWidths=[39 * mm, 82 * mm, 58 * mm], repeatRows=1)
    style = [
        ("BACKGROUND", (0, 0), (-1, 0), NAVY),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("GRID", (0, 0), (-1, -1), 0.45, OUTLINE),
        ("LEFTPADDING", (0, 0), (-1, -1), 7),
        ("RIGHTPADDING", (0, 0), (-1, -1), 7),
        ("TOPPADDING", (0, 0), (-1, -1), 6),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
    ]
    for row in range(1, len(data)):
        style.append(
            ("BACKGROUND", (0, row), (-1, row), WHITE if row % 2 else PALE)
        )
    table.setStyle(TableStyle(style))
    return table


def architecture_table():
    row1 = [
        p("ANDROID PHONE<br/><font color='#60726E'>GPS + motion</font>", "center"),
        p(">", "center"),
        p("API GATEWAY<br/><font color='#60726E'>JWT protected</font>", "center"),
        p(">", "center"),
        p("LAMBDA<br/><font color='#60726E'>App logic</font>", "center"),
    ]
    row2 = [
        p("FAMILY APP<br/><font color='#60726E'>Approved access</font>", "center"),
        p(">", "center"),
        p("COGNITO<br/><font color='#60726E'>Identity</font>", "center"),
        p(">", "center"),
        p("DYNAMODB<br/><font color='#60726E'>Private data</font>", "center"),
    ]
    row3 = [
        p("REKOGNITION<br/><font color='#60726E'>Helmet AI</font>", "center"),
        p("<", "center"),
        p("LAMBDA", "center"),
        p(">", "center"),
        p("LOCATION + SNS<br/><font color='#60726E'>Routes + alerts</font>", "center"),
    ]
    table = Table(
        [row1, row2, row3],
        colWidths=[39 * mm, 8 * mm, 39 * mm, 8 * mm, 52 * mm],
        rowHeights=[22 * mm, 22 * mm, 22 * mm],
        hAlign="CENTER",
    )
    style = [
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("BACKGROUND", (0, 0), (0, 0), PALE_GREEN),
        ("BACKGROUND", (2, 0), (2, 0), PALE),
        ("BACKGROUND", (4, 0), (4, 0), PALE_GREEN),
        ("BACKGROUND", (0, 1), (0, 1), PALE_GREEN),
        ("BACKGROUND", (2, 1), (2, 1), PALE),
        ("BACKGROUND", (4, 1), (4, 1), PALE_GREEN),
        ("BACKGROUND", (0, 2), (0, 2), PALE),
        ("BACKGROUND", (2, 2), (2, 2), PALE_GREEN),
        ("BACKGROUND", (4, 2), (4, 2), PALE),
    ]
    for row in range(3):
        for col in (0, 2, 4):
            style.append(("BOX", (col, row), (col, row), 0.7, OUTLINE))
    table.setStyle(TableStyle(style))
    return table


def draw_page(canvas, doc):
    page = canvas.getPageNumber()
    if page == 1:
        canvas.saveState()
        canvas.setFillColor(NAVY)
        canvas.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
        canvas.setFillColor(colors.HexColor("#173E36"))
        canvas.circle(PAGE_W - 15 * mm, PAGE_H - 18 * mm, 42 * mm, fill=1, stroke=0)
        canvas.setFillColor(colors.HexColor("#0F332C"))
        canvas.circle(5 * mm, 12 * mm, 38 * mm, fill=1, stroke=0)
        canvas.restoreState()
        return

    canvas.saveState()
    canvas.setFillColor(GREEN)
    canvas.roundRect(15 * mm, PAGE_H - 16 * mm, 5 * mm, 5 * mm, 1.2 * mm, fill=1, stroke=0)
    canvas.setFont("Segoe-Bold", 8)
    canvas.setFillColor(INK)
    canvas.drawString(23 * mm, PAGE_H - 12.5 * mm, "RIDEGUARDIAN AI")
    canvas.setStrokeColor(OUTLINE)
    canvas.line(15 * mm, PAGE_H - 19 * mm, PAGE_W - 15 * mm, PAGE_H - 19 * mm)
    canvas.setFont("Segoe", 7.5)
    canvas.setFillColor(MUTED)
    canvas.drawString(15 * mm, 10 * mm, "Client product overview  |  Generated from the implemented Flutter app")
    canvas.drawRightString(PAGE_W - 15 * mm, 10 * mm, "Page %d" % page)
    canvas.restoreState()


def build_story():
    story = []

    cover_text = [
        p("SMART MOTORCYCLE SAFETY", "cover_eyebrow"),
        p("RideGuardian<br/>AI", "cover_title"),
        p(
            "One tap starts a connected safety companion that monitors the ride, "
            "responds to possible danger, finds medical care, and keeps approved "
            "family members informed.",
            "cover_body",
        ),
        Spacer(1, 8 * mm),
        p("FLUTTER ANDROID APP  /  SERVERLESS AWS BACKEND", "cover_small"),
        Spacer(1, 4 * mm),
        p(
            "Client overview - implemented product, user journey, architecture, "
            "security, delivery status, and production roadmap.",
            "cover_small",
        ),
    ]
    cover_phone = screenshot("01-home-dashboard.png", 66 * mm)
    cover = Table(
        [[cover_text, cover_phone]],
        colWidths=[98 * mm, 70 * mm],
        hAlign="LEFT",
    )
    cover.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (0, 0), 0),
                ("RIGHTPADDING", (0, 0), (0, 0), 12),
                ("BACKGROUND", (1, 0), (1, 0), WHITE),
                ("BOX", (1, 0), (1, 0), 1, colors.HexColor("#42645C")),
                ("LEFTPADDING", (1, 0), (1, 0), 9),
                ("RIGHTPADDING", (1, 0), (1, 0), 9),
                ("TOPPADDING", (1, 0), (1, 0), 9),
                ("BOTTOMPADDING", (1, 0), (1, 0), 9),
            ]
        )
    )
    story.extend([Spacer(1, 20 * mm), cover])

    story.append(PageBreak())
    story.extend(
        section_header(
            "01",
            "The product in one minute",
            "A simple safety experience for the rider and clear, permission-controlled reassurance for the family.",
        )
    )
    summary_cards = Table(
        [
            [
                card(
                    "For the rider",
                    "One button starts GPS, speed, motion, impact, route, scoring, and cloud monitoring. The same button ends the ride and stops continuous services.",
                    GREEN,
                ),
                card(
                    "For the family",
                    "Only accepted guardians can retrieve a shared rider's state, speed, score, last update, authorized location, and emergency alerts.",
                    AMBER,
                ),
            ]
        ],
        colWidths=[89.5 * mm, 89.5 * mm],
    )
    summary_cards.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (0, 0), 5),
                ("LEFTPADDING", (1, 0), (1, 0), 5),
            ]
        )
    )
    story.append(summary_cards)
    story.append(Spacer(1, 8 * mm))
    story.append(p("The rider journey", "h2"))
    journey = Table(
        [
            [
                p("<b>1</b><br/>Verify account", "center"),
                p("<b>2</b><br/>Start ride", "center"),
                p("<b>3</b><br/>Monitor safety", "center"),
                p("<b>4</b><br/>Respond if needed", "center"),
                p("<b>5</b><br/>Save history", "center"),
            ]
        ],
        colWidths=[35.8 * mm] * 5,
        rowHeights=[25 * mm],
    )
    journey.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), PALE_GREEN),
                ("GRID", (0, 0), (-1, -1), 0.7, WHITE),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ]
        )
    )
    story.append(journey)
    story.append(Spacer(1, 7 * mm))
    story.append(p("What makes it easy to understand", "h2"))
    story.append(
        bullet_list(
            [
                "<b>One persistent control:</b> no separate switches for GPS, sensors, cloud tracking, and ride scoring.",
                "<b>High-visibility states:</b> green means active/safe; red marks stop and emergency actions.",
                "<b>Plain-language feedback:</b> riding, safe, offline, alert sent, and system status are visible.",
                "<b>Privacy by invitation:</b> family sharing is not automatic and can only follow an accepted relationship.",
            ],
            9.5,
        )
    )
    story.append(Spacer(1, 5 * mm))
    note = Table(
        [[p("<b>Screenshot note.</b> All frames in this document are real rendered Flutter widgets. Names, locations, and ride numbers are representative presentation data, not customer records.", "body_dark")]],
        colWidths=[179 * mm],
    )
    note.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#FFF5DF")),
                ("BOX", (0, 0), (-1, -1), 0.7, colors.HexColor("#F1D79D")),
                ("LEFTPADDING", (0, 0), (-1, -1), 12),
                ("RIGHTPADDING", (0, 0), (-1, -1), 12),
                ("TOPPADDING", (0, 0), (-1, -1), 10),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    story.append(note)

    walkthrough_page(
        story,
        "02",
        "Secure access",
        "Individual, verified accounts protect both rider and guardian experiences.",
        "00-secure-sign-in.png",
        "Secure Cognito sign-in frame",
        [
            ("What the client sees", "h2"),
            (
                "A focused account screen with email, password, account creation, "
                "and a clear AWS Cognito trust message.",
                "body",
            ),
            [
                "Email registration and verification code",
                "Secure sign-in and sign-out",
                "Automatic token refresh",
                "Separate accounts for riders and guardians",
            ],
            ("Why it matters", "h2"),
            (
                "There are no AWS access keys or user passwords compiled into the "
                "application. Private API requests carry a short-lived Cognito JWT.",
                "body",
            ),
            card(
                "Privacy starts here",
                "A guardian must sign in, receive an invitation, and accept it before rider status can be requested.",
                GREEN,
            ),
        ],
    )

    walkthrough_page(
        story,
        "03",
        "One control for the whole ride",
        "The persistent Start/End button is the operational center of the application.",
        "01-home-dashboard.png",
        "Active-ride dashboard with master control",
        [
            ("Starting a ride activates", "h2"),
            [
                "Precise GPS and live location",
                "Current speed, maximum speed, and distance",
                "Accelerometer and gyroscope monitoring",
                "Harsh movement and possible-impact rules",
                "Family location heartbeats",
                "Ride scoring and history collection",
            ],
            ("Ending a ride", "h2"),
            (
                "The same button stops sensor subscriptions and cloud heartbeats, "
                "publishes a final SAFE state, and saves the ride summary.",
                "body",
            ),
            card(
                "Resource-aware by design",
                "The continuous phone services are active only during a ride. The AWS backend is serverless and performs work only when requests arrive.",
                GREEN,
            ),
        ],
    )

    walkthrough_page(
        story,
        "04",
        "Live ride and medical routing",
        "The rider gets essential navigation and safety information without visual clutter.",
        "02-live-tracking.png",
        "Live tracking, nearby hospitals, and route estimate",
        [
            ("Live ride information", "h2"),
            [
                "Tracking state and current speed",
                "Current GPS coordinates",
                "Nearby medical facilities",
                "Selected hospital distance and estimated time",
            ],
            ("AWS-powered search", "h2"),
            (
                "Amazon Location performs the real nearby-place search and scooter-route "
                "calculation. The selected location can be handed to Google Maps for navigation.",
                "body",
            ),
            card(
                "Private by default",
                "The rider's live coordinates are sent through an authenticated API and are exposed only to accepted guardians.",
                GREEN,
            ),
        ],
    )

    walkthrough_page(
        story,
        "05",
        "Safety center",
        "Protection tools and system health are visible in one place.",
        "03-safety-center.png",
        "Safety score, AI check, hospital search, and SOS",
        [
            ("Protection tools", "h2"),
            [
                "Safety score and detected-risk count",
                "Pretrained AI helmet assessment",
                "Nearby hospital search",
                "Manual emergency SOS",
            ],
            ("System status", "h2"),
            (
                "The app clearly shows whether speed monitoring, impact detection, "
                "rider behavior analysis, and family updates are active or standing by.",
                "body",
            ),
            card(
                "No custom model training",
                "Helmet assessment calls the pretrained AWS Rekognition protective-equipment capability. The MVP does not require a training dataset.",
                AMBER,
            ),
        ],
    )

    walkthrough_page(
        story,
        "06",
        "Possible-accident response",
        "A high-visibility countdown balances urgent response with false-alarm control.",
        "06-accident-countdown.png",
        "Possible-impact countdown with cancel action",
        [
            ("How it responds", "h2"),
            [
                "A strong sensor pattern is marked as a possible impact",
                "The screen opens a 20-second cancellation window",
                "A safe rider can cancel the alert immediately",
                "If not cancelled, the latest location and reason are published",
                "Manual SOS remains available at any time",
            ],
            ("Why the countdown exists", "h2"),
            (
                "Phone motion can be caused by drops, potholes, or sudden handling. "
                "The countdown gives a conscious rider a clear way to prevent an unnecessary emergency.",
                "body",
            ),
            card(
                "Safety MVP",
                "Impact thresholds must be calibrated through controlled, consented road testing before production use.",
                RED,
            ),
        ],
    )

    walkthrough_page(
        story,
        "07",
        "Understand every ride",
        "Cloud history turns safety activity into a progress record.",
        "04-ride-history.png",
        "Private cloud ride-history summaries",
        [
            ("Each ride summary includes", "h2"),
            [
                "Ride date and start time",
                "Distance and duration",
                "Maximum speed",
                "Detected event count",
                "Final safety score",
            ],
            ("Client value", "h2"),
            (
                "The rider can understand trends rather than viewing safety as a one-time "
                "warning. History is private to the signed-in account and stored in DynamoDB.",
                "body",
            ),
            card(
                "Explainable score",
                "The 0-100 score uses deterministic penalties for overspeed, harsh braking, acceleration, sharp turns, and possible impacts.",
                GREEN,
            ),
        ],
    )

    walkthrough_page(
        story,
        "08",
        "Family guardian circle",
        "The rider decides who can see their safety status.",
        "05-family-guardian.png",
        "Permission-controlled guardian and shared-rider view",
        [
            ("Invitation workflow", "h2"),
            [
                "Rider invites the guardian's exact account email",
                "Guardian signs in and accepts",
                "Backend creates the reciprocal relationship",
                "Every live-status request checks permission again",
            ],
            ("What an approved guardian can see", "h2"),
            [
                "Riding, safe, or offline state",
                "Safety score, speed, and last update",
                "Authorized last location",
                "In-app emergency alerts",
            ],
            card(
                "Consent is explicit",
                "Creating a family account alone does not reveal a rider. An accepted invitation is required.",
                GREEN,
            ),
        ],
    )

    story.append(PageBreak())
    story.extend(
        section_header(
            "09",
            "Implemented capability matrix",
            "The current MVP connects the visible client experience to working mobile and AWS components.",
        )
    )
    rows = [
        ("Account security", "Verified registration, login, logout", "Cognito + Amplify"),
        ("Universal ride control", "One persistent Start/End button", "Flutter lifecycle controller"),
        ("Speed monitoring", "Live and maximum km/h", "Android GPS"),
        ("Location tracking", "Coordinates and cloud heartbeats", "GPS + API + DynamoDB"),
        ("Ride distance", "Distance along route points", "On-device calculation"),
        ("Rider behavior", "Harsh braking, acceleration, turns", "Accelerometer + gyroscope"),
        ("Accident assistance", "Countdown and automatic SOS", "Motion rules + Lambda + SNS"),
        ("Manual SOS", "Rider-triggered location alert", "Authenticated emergency API"),
        ("Helmet check", "Photo confidence assessment", "Pretrained Rekognition PPE"),
        ("Nearby hospitals", "Medical places near GPS fix", "Amazon Location Places"),
        ("Route estimate", "Scooter distance and duration", "Amazon Location Routes"),
        ("Safety score", "Clear 0-100 result", "Deterministic scoring"),
        ("Ride history", "Private completed-ride summaries", "DynamoDB"),
        ("Family sharing", "Accepted rider/guardian relationship", "Cognito + DynamoDB"),
        ("Family status", "State, speed, score, time, location", "Permission-checked API"),
        ("Resource control", "Sensors and heartbeats stop on End", "Central ride lifecycle"),
    ]
    story.append(feature_table(rows))
    story.append(Spacer(1, 7 * mm))
    story.append(
        p(
            "<b>Key distinction:</b> AI is used where a pretrained visual model adds value. "
            "Core ride monitoring remains deterministic, understandable, and responsive on the phone.",
            "body_dark",
        )
    )

    story.append(PageBreak())
    story.extend(
        section_header(
            "10",
            "AWS architecture and security",
            "A serverless design keeps operations simple and avoids a permanently running application server.",
        )
    )
    story.append(architecture_table())
    story.append(Spacer(1, 7 * mm))
    services = [
        ("Cognito User Pool", "Verified accounts and secure tokens"),
        ("API Gateway", "Public health route and JWT-protected private routes"),
        ("Lambda - Python 3.13 ARM64", "Application logic and permission checks"),
        ("DynamoDB", "Live state, rides, invitations, relationships, alerts"),
        ("Rekognition", "Pretrained protective-equipment assessment"),
        ("Amazon Location", "Nearby hospitals and scooter routes"),
        ("SNS", "Encrypted emergency-alert topic"),
        ("CloudFormation / SAM", "Repeatable deployment"),
    ]
    service_data = [[p("AWS service", "table_head"), p("Responsibility", "table_head")]]
    for name, value in services:
        service_data.append([p(name, "table_bold"), p(value, "table")])
    service_table = Table(service_data, colWidths=[64 * mm, 115 * mm], repeatRows=1)
    service_table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), NAVY),
                ("GRID", (0, 0), (-1, -1), 0.45, OUTLINE),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 7),
                ("RIGHTPADDING", (0, 0), (-1, -1), 7),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
        )
    )
    story.append(service_table)
    story.append(Spacer(1, 6 * mm))
    story.append(p("Backend safeguards", "h2"))
    story.append(
        bullet_list(
            [
                "JWT authentication on every private route",
                "Permission checks for guardian access",
                "No AWS keys or passwords inside the APK",
                "DynamoDB encryption, point-in-time recovery, and retained data protection",
                "Encrypted SNS topic and scoped Lambda permissions",
                "Pay-per-request storage and request-driven compute",
            ],
            8.8,
        )
    )

    story.append(PageBreak())
    story.extend(
        section_header(
            "11",
            "How to demonstrate the product",
            "A two-account walkthrough makes both sides of the safety experience easy for a client to understand.",
        )
    )
    demo = Table(
        [
            [
                [
                    p("Rider device", "h2"),
                    bullet_list(
                        [
                            "Create and verify the rider account",
                            "Allow location, camera, motion, and notification permissions",
                            "Press Start ride safety systems",
                            "Show Live, Safety, and Ride history",
                            "Invite the family member's exact email",
                            "Press End ride to stop services and save the summary",
                        ]
                    ),
                ],
                [
                    p("Family device", "h2"),
                    bullet_list(
                        [
                            "Create and verify a second account",
                            "Open Family and refresh invitations",
                            "Accept the rider's invitation",
                            "Open the shared rider status",
                            "Show state, speed, score, update time, and location",
                            "Refresh the Family view to retrieve alerts",
                        ]
                    ),
                ],
            ]
        ],
        colWidths=[89.5 * mm, 89.5 * mm],
    )
    demo.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), PALE),
                ("BOX", (0, 0), (-1, -1), 0.7, OUTLINE),
                ("LINEAFTER", (0, 0), (0, 0), 0.7, OUTLINE),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 14),
                ("RIGHTPADDING", (0, 0), (-1, -1), 14),
                ("TOPPADDING", (0, 0), (-1, -1), 10),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 10),
            ]
        )
    )
    story.append(demo)
    story.append(Spacer(1, 7 * mm))
    story.append(p("Current delivery status", "h2"))
    status_data = [
        [p("AWS backend", "table_bold"), p("Deployed and healthy - UPDATE_COMPLETE", "table")],
        [p("API health", "table_bold"), p("HTTP 200", "table")],
        [p("Flutter analyzer", "table_bold"), p("No issues", "table")],
        [p("Widget tests", "table_bold"), p("Passing", "table")],
        [p("Screenshot render test", "table_bold"), p("Passing at 430 x 932", "table")],
        [p("Android debug APK", "table_bold"), p("Built successfully", "table")],
    ]
    status_table = Table(status_data, colWidths=[58 * mm, 121 * mm])
    status_table.setStyle(
        TableStyle(
            [
                ("GRID", (0, 0), (-1, -1), 0.45, OUTLINE),
                ("BACKGROUND", (0, 0), (0, -1), PALE_GREEN),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 6),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
            ]
        )
    )
    story.append(status_table)
    story.append(Spacer(1, 6 * mm))
    story.append(
        p(
            "<b>APK:</b> build/app/outputs/flutter-apk/app-debug.apk<br/>"
            "<b>SHA-256:</b> 106E963A23C5118725CCC39C58D133027C01A43E9FE17C5E1CFEFDA20EF29755",
            "small",
        )
    )

    story.append(PageBreak())
    story.extend(
        section_header(
            "12",
            "Production roadmap",
            "The MVP is working, but a safety product requires careful validation and operational preparation before public release.",
        )
    )
    roadmap = [
        (
            "1. Controlled road calibration",
            "Calibrate impact and behavior thresholds across different phones, mounting positions, motorcycles, and road conditions.",
        ),
        (
            "2. Push and SMS delivery",
            "Connect Firebase Cloud Messaging and/or an approved SMS channel. The current Family view retrieves stored alerts; SNS is provisioned without customer phone subscriptions.",
        ),
        (
            "3. Privacy lifecycle",
            "Add explicit consent, retention settings, guardian removal, data export, and account deletion.",
        ),
        (
            "4. Store-policy readiness",
            "Complete Google Play background-location disclosure, policy review, release signing, and permission education.",
        ),
        (
            "5. Device validation",
            "Add physical-device integration tests, accessibility checks, battery profiling, network-loss scenarios, and emergency drills.",
        ),
        (
            "6. Production operations",
            "Add alarms, dashboards, audit trails, abuse controls, throttling, delivery monitoring, and incident response.",
        ),
    ]
    roadmap_rows = []
    for title, body in roadmap:
        roadmap_rows.append([p(title, "card_title"), p(body, "card_body")])
    roadmap_table = Table(roadmap_rows, colWidths=[52 * mm, 127 * mm])
    roadmap_table.setStyle(
        TableStyle(
            [
                ("GRID", (0, 0), (-1, -1), 0.5, OUTLINE),
                ("BACKGROUND", (0, 0), (0, -1), PALE_GREEN),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                ("TOPPADDING", (0, 0), (-1, -1), 9),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 9),
            ]
        )
    )
    story.append(roadmap_table)
    story.append(Spacer(1, 8 * mm))
    warning = Table(
        [[p("<b>Important:</b> RideGuardian is a working safety MVP, not a certified crash-detection or medical device. It must not replace responsible riding, protective equipment, or local emergency services.", "body_dark")]],
        colWidths=[179 * mm],
    )
    warning.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#FFE9E9")),
                ("BOX", (0, 0), (-1, -1), 0.8, colors.HexColor("#E9A3A3")),
                ("LINEBEFORE", (0, 0), (0, -1), 4, RED),
                ("LEFTPADDING", (0, 0), (-1, -1), 12),
                ("RIGHTPADDING", (0, 0), (-1, -1), 12),
                ("TOPPADDING", (0, 0), (-1, -1), 10),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    story.append(warning)
    story.append(Spacer(1, 13 * mm))
    story.append(p("One tap for a safer ride and a better-informed family.", "title"))
    story.append(
        p(
            "RideGuardian AI combines a clear mobile experience with authenticated, "
            "serverless AWS services to create a credible foundation for the next "
            "stage of product validation.",
            "body",
        )
    )

    return story


def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    doc = SimpleDocTemplate(
        str(OUTPUT_FILE),
        pagesize=A4,
        rightMargin=15 * mm,
        leftMargin=15 * mm,
        topMargin=24 * mm,
        bottomMargin=18 * mm,
        title="RideGuardian AI - Client Product Overview",
        author="RideGuardian AI",
        subject="Implemented Flutter and AWS motorcycle safety application",
        creator="RideGuardian AI project",
    )
    doc.build(build_story(), onFirstPage=draw_page, onLaterPages=draw_page)
    print(OUTPUT_FILE)


if __name__ == "__main__":
    main()
