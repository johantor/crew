using EPiServer.Web.Mvc;
using EvalSite.Models.Pages;
using EvalSite.Models.ViewModels;
using EvalSite.Services;
using Microsoft.AspNetCore.Mvc;

namespace EvalSite.Controllers;

public class StartPageController(ArticleService articleService) : PageController<StartPage>
{
    private const int LatestArticleCount = 5;

    public IActionResult Index(StartPage currentPage) =>
        View(new StartPageViewModel(currentPage, articleService.GetLatest(currentPage.ContentLink, LatestArticleCount)));
}
