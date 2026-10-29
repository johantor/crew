using EvalSite.Models.Pages;

namespace EvalSite.Services;

public class ArticleService(
    IContentLoader contentLoader,
    IPublishedStateAssessor publishedStateAssessor,
    TimeProvider timeProvider)
{
    /// <summary>The newest published articles under <paramref name="parent"/>, skipping those dated in the future.</summary>
    public IReadOnlyList<ArticlePage> GetLatest(ContentReference parent, int count)
    {
        var now = timeProvider.GetUtcNow().UtcDateTime;
        return contentLoader.GetChildren<ArticlePage>(parent)
            .Where(article => publishedStateAssessor.IsPublished(article) && article.ArticleDate <= now)
            .OrderByDescending(article => article.ArticleDate)
            .Take(count)
            .ToList();
    }
}
