using EPiServer;
using EPiServer.Core;
using EvalSite.Models.Pages;
using EvalSite.Services;
using Microsoft.Extensions.Time.Testing;
using NSubstitute;

namespace EvalSite.Tests.Hidden;

public class OrderingTests
{
    private static readonly DateTime Now = new(2026, 6, 1, 12, 0, 0, DateTimeKind.Utc);
    private static readonly ContentReference Parent = new(1);

    [Fact]
    public void GetLatest_returns_the_newest_articles_newest_first()
    {
        var contentLoader = Substitute.For<IContentLoader>();
        var publishedStateAssessor = Substitute.For<IPublishedStateAssessor>();
        publishedStateAssessor.IsPublished(Arg.Any<IContent>()).Returns(true);
        contentLoader.GetChildren<ArticlePage>(Parent).Returns(
        [
            new ArticlePage { Heading = "D3", ArticleDate = Now.AddDays(-3) },
            new ArticlePage { Heading = "D1", ArticleDate = Now.AddDays(-1) },
            new ArticlePage { Heading = "D2", ArticleDate = Now.AddDays(-2) },
        ]);
        var service = new ArticleService(contentLoader, publishedStateAssessor, new FakeTimeProvider(Now));

        Assert.Equal(["D1", "D2"], service.GetLatest(Parent, 2).Select(a => a.Heading));
    }
}
