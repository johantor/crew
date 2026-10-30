using EPiServer;
using EPiServer.Core;
using EvalSite.Models.Pages;
using EvalSite.Services;
using Microsoft.Extensions.Time.Testing;
using NSubstitute;

namespace EvalSite.Tests;

public class ArticleServiceTests
{
    private static readonly DateTime Now = new(2026, 6, 1, 12, 0, 0, DateTimeKind.Utc);
    private static readonly ContentReference Parent = new(1);

    private readonly IContentLoader _contentLoader = Substitute.For<IContentLoader>();
    private readonly IPublishedStateAssessor _publishedStateAssessor = Substitute.For<IPublishedStateAssessor>();
    private readonly ArticleService _service;

    public ArticleServiceTests()
    {
        _publishedStateAssessor.IsPublished(Arg.Any<IContent>()).Returns(true);
        _service = new ArticleService(_contentLoader, _publishedStateAssessor, new FakeTimeProvider(Now));
    }

    [Fact]
    public void GetLatest_returns_newest_first()
    {
        var older = Article("Older", Now.AddDays(-2));
        var newer = Article("Newer", Now.AddDays(-1));
        Children(older, newer);

        var result = _service.GetLatest(Parent, 5);

        Assert.Equal(["Newer", "Older"], result.Select(a => a.Heading));
    }

    [Fact]
    public void GetLatest_takes_at_most_count()
    {
        Children(Article("A", Now.AddDays(-1)), Article("B", Now.AddDays(-2)), Article("C", Now.AddDays(-3)));

        var result = _service.GetLatest(Parent, 2);

        Assert.Equal(["A", "B"], result.Select(a => a.Heading));
    }

    [Fact]
    public void GetLatest_skips_articles_dated_in_the_future()
    {
        Children(Article("Future", Now.AddDays(1)), Article("Past", Now.AddDays(-1)));

        var result = _service.GetLatest(Parent, 5);

        Assert.Equal(["Past"], result.Select(a => a.Heading));
    }

    [Fact]
    public void GetLatest_skips_unpublished_articles()
    {
        var draft = Article("Draft", Now.AddDays(-1));
        Children(draft, Article("Published", Now.AddDays(-2)));
        _publishedStateAssessor.IsPublished(draft).Returns(false);

        var result = _service.GetLatest(Parent, 5);

        Assert.Equal(["Published"], result.Select(a => a.Heading));
    }

    private static ArticlePage Article(string heading, DateTime date) => new() { Heading = heading, ArticleDate = date };

    private void Children(params ArticlePage[] articles) =>
        _contentLoader.GetChildren<ArticlePage>(Parent).Returns(articles);
}
