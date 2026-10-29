using EPiServer.Web.Mvc;
using EvalSite.Models.Pages;
using Microsoft.AspNetCore.Mvc;

namespace EvalSite.Controllers;

public class ArticlePageController : PageController<ArticlePage>
{
    public IActionResult Index(ArticlePage currentPage) => View(currentPage);
}
