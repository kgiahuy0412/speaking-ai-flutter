from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts" / "design-qa" / "lesson-flow"
SOURCE_JOURNEY = Path(
    r"C:\Users\Windows\AppData\Local\Temp\codex-clipboard-5db6e79d-c118-4910-9712-b611729ba379.png"
)
SOURCE_PRACTICE = Path(
    r"C:\Users\Windows\AppData\Local\Temp\codex-clipboard-3b40f415-bea1-492a-979e-656aa40f5172.png"
)
SOURCE_COMPLETION = Path(
    r"C:\Users\Windows\AppData\Local\Temp\codex-clipboard-e2481a72-d554-45fc-9783-2a49933bb4ce.png"
)
GOLDENS = ROOT / "test" / "features" / "listening" / "goldens"


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    name = "Roboto-Bold.ttf" if bold else "Roboto-Regular.ttf"
    return ImageFont.truetype(str(ROOT / "assets" / "fonts" / name), size)


def labeled_panel(image: Image.Image, label: str, width: int) -> Image.Image:
    margin = 24
    header = 56
    scale = min(1.0, (width - margin * 2) / image.width)
    rendered = image.resize(
        (round(image.width * scale), round(image.height * scale)),
        Image.Resampling.LANCZOS,
    )
    panel = Image.new("RGB", (width, rendered.height + header + margin), "#F8F7FF")
    draw = ImageDraw.Draw(panel)
    draw.text((margin, 17), label, fill="#142451", font=font(22, bold=True))
    panel.paste(rendered, ((width - rendered.width) // 2, header))
    return panel


def combine_horizontal(images: list[Image.Image], gap: int = 18) -> Image.Image:
    canvas = Image.new(
        "RGB",
        (sum(image.width for image in images) + gap * (len(images) - 1), max(image.height for image in images)),
        "#FFFFFF",
    )
    x = 0
    for image in images:
        canvas.paste(image, (x, 0))
        x += image.width + gap
    return canvas


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)

    source_journey = Image.open(SOURCE_JOURNEY).convert("RGB")
    journey = Image.open(GOLDENS / "topic-lesson-journey-390x844.png").convert("RGB")
    intro = Image.open(GOLDENS / "lesson-intro-390x844.png").convert("RGB")
    implementation_journey = combine_horizontal([journey, intro])
    source_panel = labeled_panel(source_journey, "Mẫu đã chọn", 920)
    implementation_panel = labeled_panel(
        implementation_journey,
        "Flutter đã triển khai · 390 × 844 mỗi màn hình",
        920,
    )
    journey_comparison = Image.new(
        "RGB",
        (
            920,
            source_panel.height + implementation_panel.height + 18,
        ),
        "#E9E7F8",
    )
    journey_comparison.paste(source_panel, (0, 0))
    journey_comparison.paste(
        implementation_panel,
        (0, source_panel.height + 18),
    )
    journey_comparison.save(
        OUTPUT / "comparison-topic-journey-and-intro.png",
        optimize=True,
    )

    source_practice = Image.open(SOURCE_PRACTICE).convert("RGB")
    practice = Image.open(GOLDENS / "lesson-practice-390x844.png").convert("RGB")
    practice_comparison = combine_horizontal(
        [
            labeled_panel(source_practice, "Mẫu đã chọn", 470),
            labeled_panel(practice, "Flutter đã triển khai · 390 × 844", 470),
        ],
        gap=18,
    )
    practice_comparison.save(
        OUTPUT / "comparison-sentence-practice.png",
        optimize=True,
    )

    source_completion = Image.open(SOURCE_COMPLETION).convert("RGB")
    completion = Image.open(GOLDENS / "lesson-completion-390x844.png").convert("RGB")
    completion_comparison = combine_horizontal(
        [
            labeled_panel(source_completion, "Màn hoàn thành trước khi cải thiện", 500),
            labeled_panel(
                completion,
                "Flutter đã cải thiện · 390 × 844",
                500,
            ),
        ],
        gap=18,
    )
    completion_comparison.save(
        OUTPUT / "comparison-completion-celebration.png",
        optimize=True,
    )


if __name__ == "__main__":
    main()
