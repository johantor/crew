using EPiServer.ServiceLocation;
using EPiServer.Web.Mvc;
using EPiServer.Web.Routing;
using EvalSite.Models.Blocks;
using EvalSite.Models.ViewModels;
using Microsoft.AspNetCore.Mvc;

namespace EvalSite.Components;

public class TeaserBlockComponent : BlockComponent<TeaserBlock>
{
    protected override IViewComponentResult InvokeComponent(TeaserBlock currentContent)
    {
        var urlResolver = ServiceLocator.Current.GetInstance<IUrlResolver>();
        var url = ContentReference.IsNullOrEmpty(currentContent.Link) ? null : urlResolver.GetUrl(currentContent.Link);
        return View(new TeaserBlockViewModel(currentContent, url));
    }
}
