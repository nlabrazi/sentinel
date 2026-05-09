module ApplicationHelper
  FONT_AWESOME_ALIASES = {
    magnifying_glass: "magnifying-glass",
    right_from_bracket: "right-from-bracket",
    arrow_up_right_from_square: "arrow-up-right-from-square",
    heart_pulse: "heart-pulse"
  }.freeze

  def fa_icon(name, class_name: "h-4 w-4", title: nil, style: "solid")
    icon_name = FONT_AWESOME_ALIASES.fetch(name) do
      name.to_s.tr("_", "-")
    end

    style_class = case style.to_s
    when "regular" then "fa-regular"
    when "brands" then "fa-brands"
    else "fa-solid"
    end

    tag.i(
      class: "#{style_class} fa-#{icon_name} #{class_name}",
      title: title,
      role: title.present? ? "img" : nil,
      "aria-hidden": title.present? ? nil : "true"
    )
  end
end
