<?php

declare(strict_types=1);

namespace Shop;

use Acme\Slugify\Slugify;

final class ProductSlug
{
    public function forName(string $name): string
    {
        return Slugify::create()->slugify($name);
    }
}
