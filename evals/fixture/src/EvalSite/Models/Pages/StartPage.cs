using System.ComponentModel.DataAnnotations;
using EvalSite.Models.Blocks;

namespace EvalSite.Models.Pages;

[ContentType(DisplayName = "Start page", GUID = "faa7ac33-53ab-4a78-a559-b73eeeffd994", GroupName = "Pages")]
public class StartPage : PageData
{
    [CultureSpecific]
    [Display(Name = "Heading", Order = 10)]
    public virtual string? Heading { get; set; }

    [Display(Name = "Main content area", Order = 20)]
    [AllowedTypes(typeof(TeaserBlock))]
    public virtual ContentArea? MainContentArea { get; set; }
}
