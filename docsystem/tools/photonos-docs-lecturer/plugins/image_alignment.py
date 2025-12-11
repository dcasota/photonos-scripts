#!/usr/bin/env python3
"""
Image Alignment Plugin for Photon OS Documentation Lecturer

Detects pages with multiple images that lack proper alignment CSS classes.
Reports for manual review as alignment preferences vary.

Version: 1.0.0
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

from .base import BasePlugin, Issue, FixResult

__version__ = "1.0.0"


class ImageAlignmentPlugin(BasePlugin):
    """Plugin for detecting unaligned multiple images.
    
    Checks if pages with multiple images have proper CSS alignment.
    """
    
    PLUGIN_NAME = "image_alignment"
    PLUGIN_VERSION = "1.0.0"
    PLUGIN_DESCRIPTION = "Detect unaligned multiple images"
    REQUIRES_LLM = False
    FIX_ID = None  # No auto-fix - requires design decisions
    
    # CSS classes that indicate proper alignment
    ALIGNMENT_CLASSES = [
        'align-center', 'align-left', 'align-right',
        'centered', 'center',
        'img-responsive', 'img-fluid',
        'text-center', 'text-left', 'text-right',
        'mx-auto', 'd-block',
        'float-left', 'float-right',
    ]
    
    # Container classes that indicate proper wrapping
    CONTAINER_CLASSES = [
        'image-container', 'img-container',
        'figure', 'gallery', 'img-gallery',
        'images-row', 'image-row',
        'flex', 'grid',
    ]
    
    def __init__(self, llm_client: Optional[Any] = None, config: Optional[Dict] = None):
        """Initialize the image alignment plugin.
        
        Args:
            llm_client: Not used for this plugin
            config: Configuration with optional 'min_images' threshold
        """
        super().__init__(llm_client, config)
        self.min_images = config.get('min_images', 2) if config else 2
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect pages with unaligned multiple images.
        
        Args:
            content: HTML content
            url: URL of the page
            **kwargs: Must include 'soup' for BeautifulSoup object
            
        Returns:
            List of image alignment issues
        """
        issues = []
        soup = kwargs.get('soup')
        
        if not soup:
            return issues
        
        # Find all images
        images = soup.find_all('img')
        
        # Only check pages with multiple images
        if len(images) < self.min_images:
            return issues
        
        # Check each image for alignment classes
        unaligned_images = []
        for img in images:
            if not self._has_alignment(img):
                src = img.get('src', 'unknown')
                alt = img.get('alt', '')
                unaligned_images.append((src, alt))
        
        # Report if there are unaligned images
        if unaligned_images:
            # Check if any container has alignment classes
            has_container_alignment = self._check_container_alignment(soup)
            
            if not has_container_alignment:
                for src, alt in unaligned_images[:5]:  # Limit to first 5
                    issue = Issue(
                        category=self.PLUGIN_NAME,
                        location=f"Image: {alt[:30] if alt else src[:30]}",
                        description=f"{len(unaligned_images)} images lack alignment CSS",
                        suggestion="Add CSS alignment classes or wrap in container",
                        fixable=False,
                        metadata={
                            'total_images': len(images),
                            'unaligned_count': len(unaligned_images),
                            'src': src,
                            'alt': alt
                        }
                    )
                    issues.append(issue)
                    break  # One issue per page is enough
        
        self.increment_detected(len(issues))
        return issues
    
    def _has_alignment(self, img_tag) -> bool:
        """Check if an image has alignment CSS.
        
        Args:
            img_tag: BeautifulSoup img tag
            
        Returns:
            True if image has alignment
        """
        # Check class attribute
        classes = img_tag.get('class', [])
        if isinstance(classes, str):
            classes = classes.split()
        
        for cls in classes:
            if any(align in cls.lower() for align in self.ALIGNMENT_CLASSES):
                return True
        
        # Check style attribute
        style = img_tag.get('style', '')
        if style:
            style_lower = style.lower()
            if any(prop in style_lower for prop in ['margin', 'float', 'display', 'text-align']):
                return True
        
        # Check parent elements
        parent = img_tag.parent
        for _ in range(3):  # Check up to 3 levels
            if parent:
                parent_classes = parent.get('class', [])
                if isinstance(parent_classes, str):
                    parent_classes = parent_classes.split()
                
                for cls in parent_classes:
                    if any(align in cls.lower() for align in self.ALIGNMENT_CLASSES + self.CONTAINER_CLASSES):
                        return True
                
                parent = parent.parent
            else:
                break
        
        return False
    
    def _check_container_alignment(self, soup) -> bool:
        """Check if there's a container with alignment for images.
        
        Args:
            soup: BeautifulSoup object
            
        Returns:
            True if container alignment found
        """
        for cls in self.CONTAINER_CLASSES:
            if soup.find(class_=lambda x: x and cls in x.lower() if isinstance(x, str) else False):
                return True
        
        return False
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Image alignment cannot be auto-fixed.
        
        Returns:
            FixResult indicating manual intervention required
        """
        return FixResult(
            success=False,
            error="Image alignment requires manual CSS adjustments based on design preferences"
        )
