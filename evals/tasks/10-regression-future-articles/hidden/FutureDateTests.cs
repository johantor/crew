using EPiServer;
using EPiServer.Core;
using EvalSite.Models.Pages;
using EvalSite.Services;
using Microsoft.Extensions.Time.Testing;
using NSubstitute;

namespace EvalSite.Tests.Hidden;

public class FutureDateTests
{
    private static readonly DateTime Now = new(2026, 6, 1, 12, 0, 0, DateTimeKind.Utc);
    private static readonly ContentReference Parent = new(1);

    [Fact]
    public void GetLatest_leaves_out_articles_dated_after_now()
    {
        var contentLoader = Substitute.For<IContentLoader>();
        var publishedStateAssessor = Substitute.For<IPublishedStateAssessor>();
        publishedStateAssessor.IsPublished(Arg.Any<IContent>()).Returns(true);
        contentLoader.GetChildren<ArticlePage>(Parent).Returns(
        [
            new ArticlePage { Heading = "Tomorrow", ArticleDate = Now.AddDays(1) },
            new ArticlePage { Heading = "In an hour", ArticleDate = Now.AddHours(1) },
            new ArticlePage { Heading = "Yesterday", ArticleDate = Now.AddDays(-1) },
        ]);
        var service = new ArticleService(contentLoader, publishedStateAssessor, new FakeTimeProvider(Now));

        Assert.Equal(["Yesterday"], service.GetLatest(Parent, 5).Select(a => a.Heading));
    }
}
