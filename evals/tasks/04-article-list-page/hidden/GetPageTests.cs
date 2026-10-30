using EPiServer;
using EPiServer.Core;
using EvalSite.Models.Pages;
using EvalSite.Services;
using Microsoft.Extensions.Time.Testing;
using NSubstitute;

namespace EvalSite.Tests.Hidden;

public class GetPageTests
{
    private static readonly DateTime Now = new(2026, 6, 1, 12, 0, 0, DateTimeKind.Utc);
    private static readonly ContentReference Parent = new(1);

    private readonly IContentLoader _contentLoader = Substitute.For<IContentLoader>();
    private readonly IPublishedStateAssessor _publishedStateAssessor = Substitute.For<IPublishedStateAssessor>();
    private readonly ArticleService _service;

    public GetPageTests()
    {
        _publishedStateAssessor.IsPublished(Arg.Any<IContent>()).Returns(true);
        _service = new ArticleService(_contentLoader, _publishedStateAssessor, new FakeTimeProvider(Now));
    }

    [Fact]
    public void Second_page_holds_the_next_articles_newest_first()
    {
        Children(Article("D4", -4), Article("D1", -1), Article("D3", -3), Article("D5", -5), Article("D2", -2));

        Assert.Equal(["D3", "D4"], _service.GetPage(Parent, 2, 2).Select(a => a.Heading));
    }

    [Fact]
    public void Last_page_may_be_short()
    {
        Children(Article("D1", -1), Article("D2", -2), Article("D3", -3));

        Assert.Equal(["D3"], _service.GetPage(Parent, 2, 2).Select(a => a.Heading));
    }

    [Fact]
    public void Future_and_unpublished_articles_are_not_paged()
    {
        var draft = Article("Draft", -1);
        Children(Article("Future", 1), draft, Article("D2", -2));
        _publishedStateAssessor.IsPublished(draft).Returns(false);

        Assert.Equal(["D2"], _service.GetPage(Parent, 1, 10).Select(a => a.Heading));
    }

    private static ArticlePage Article(string heading, int days) => new() { Heading = heading, ArticleDate = Now.AddDays(days) };

    private void Children(params ArticlePage[] articles) =>
        _contentLoader.GetChildren<ArticlePage>(Parent).Returns(articles);
}
