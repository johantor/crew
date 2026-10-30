using EvalSite.Models.Pages;

namespace EvalSite.Models.ViewModels;

public record StartPageViewModel(StartPage CurrentPage, IReadOnlyList<ArticlePage> LatestArticles);
