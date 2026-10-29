using System.ComponentModel.DataAnnotations;

namespace EvalSite.Models.Pages;

[ContentType(DisplayName = "Article page", GUID = "270ea843-9639-4498-ac4d-2e7ae190ecc8", GroupName = "Pages")]
public class ArticlePage : PageData
{
    [CultureSpecific]
    [Required]
    [Display(Name = "Heading", Order = 10)]
    public virtual string? Heading { get; set; }

    [CultureSpecific]
    [Display(Name = "Teaser", Order = 20)]
    public virtual string? Teaser { get; set; }

    [Display(Name = "Article date", Order = 30)]
    public virtual DateTime ArticleDate { get; set; }

    [CultureSpecific]
    [Display(Name = "Main body", Order = 40)]
    public virtual XhtmlString? MainBody { get; set; }
}
