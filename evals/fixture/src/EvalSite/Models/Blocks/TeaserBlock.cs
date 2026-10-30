using System.ComponentModel.DataAnnotations;

namespace EvalSite.Models.Blocks;

[ContentType(DisplayName = "Teaser", GUID = "da0be77b-778d-45f8-873b-a21b91c3291d", GroupName = "Blocks")]
public class TeaserBlock : BlockData
{
    [CultureSpecific]
    [Display(Name = "Heading", Order = 10)]
    public virtual string? Heading { get; set; }

    [CultureSpecific]
    [Display(Name = "Text", Order = 20)]
    public virtual string? Text { get; set; }

    [Display(Name = "Link", Order = 30)]
    public virtual ContentReference? Link { get; set; }
}
