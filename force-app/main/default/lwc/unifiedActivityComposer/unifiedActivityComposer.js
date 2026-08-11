import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createChatterPost from '@salesforce/apex/UnifiedActivityController.createChatterPost';

export default class UnifiedActivityComposer extends LightningElement {
    @api recordId;
    body = '';
    isPosting = false;
    uploadedImagesBySrc = new Map();

    richTextFormats = [
        'bold',
        'italic',
        'underline',
        'strike',
        'list',
        'indent',
        'align',
        'link',
        'image',
        'clean'
    ];

    get isEmpty() {
        return this.isRichTextEmpty(this.body);
    }

    get isDisabled() {
        return this.isEmpty || this.isPosting;
    }

    handleBodyChange(event) {
        this.body = event.detail.value;
    }

    handleImageUpload(event) {
        const { downloadUrl, contentVersionId } = event.detail || {};
        if (!contentVersionId) {
            return;
        }

        this.registerUploadedImage(contentVersionId, downloadUrl);
    }

    registerUploadedImage(contentVersionId, downloadUrl) {
        if (downloadUrl) {
            this.uploadedImagesBySrc.set(downloadUrl, contentVersionId);
            this.uploadedImagesBySrc.set(this.normalizeImageSrc(downloadUrl), contentVersionId);
        }
        this.uploadedImagesBySrc.set(contentVersionId, contentVersionId);
    }

    normalizeImageSrc(src) {
        if (!src) {
            return '';
        }

        const normalized = src.replace(/&amp;/gi, '&').trim();
        try {
            const parsed = new URL(normalized, window.location.origin);
            return `${parsed.pathname}${parsed.search}`;
        } catch (error) {
            return normalized;
        }
    }

    handleImageUploadError(event) {
        const detail = event.detail || {};
        let message = detail.error || 'There was a problem uploading the file.';

        if (detail.file?.size > 1024 * 1024) {
            message = 'Image must be 1 MB or smaller.';
        }

        this.dispatchEvent(new ShowToastEvent({
            title: 'Image upload failed',
            message,
            variant: 'error'
        }));
    }

    isRichTextEmpty(value) {
        if (!value) {
            return true;
        }
        const stripped = value
            .replace(/<[^>]*>/g, '')
            .replace(/&nbsp;/gi, ' ')
            .trim();
        return stripped.length === 0;
    }

    collectImageContentVersionIds(html) {
        const versionIds = [];
        const imgPattern = /<img[^>]+src=["']([^"']+)["'][^>]*>/gi;
        let match;

        while ((match = imgPattern.exec(html)) !== null) {
            const versionId = this.resolveContentVersionId(match[1]);
            if (versionId) {
                versionIds.push(versionId);
            }
        }

        return versionIds;
    }

    resolveContentVersionId(src) {
        if (!src) {
            return null;
        }

        const normalizedSrc = this.normalizeImageSrc(src);
        if (this.uploadedImagesBySrc.has(src)) {
            return this.uploadedImagesBySrc.get(src);
        }
        if (this.uploadedImagesBySrc.has(normalizedSrc)) {
            return this.uploadedImagesBySrc.get(normalizedSrc);
        }

        for (const [key, versionId] of this.uploadedImagesBySrc.entries()) {
            if (normalizedSrc.includes(key) || key.includes(normalizedSrc)) {
                return versionId;
            }
        }

        const versionMatch = normalizedSrc.match(/versionId=([a-zA-Z0-9]{15,18})/i);
        if (versionMatch) {
            return versionMatch[1];
        }

        const downloadMatch = normalizedSrc.match(/\/version\/download\/([a-zA-Z0-9]{15,18})/i);
        if (downloadMatch) {
            return downloadMatch[1];
        }

        const idMatch = normalizedSrc.match(/(?:refid|id)=([a-zA-Z0-9]{15,18})/i);
        if (idMatch && idMatch[1].startsWith('068')) {
            return idMatch[1];
        }

        return null;
    }

    async handlePost() {
        if (this.isEmpty) {
            return;
        }

        this.isPosting = true;
        try {
            const imageContentVersionIds = this.collectImageContentVersionIds(this.body);
            await createChatterPost({
                recordId: this.recordId,
                body: this.body,
                imageContentVersionIds
            });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Post created',
                variant: 'success'
            }));
            this.dispatchEvent(new CustomEvent('success'));
            this.body = '';
            this.uploadedImagesBySrc = new Map();
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error creating post',
                message: this.extractErrorMessage(error),
                variant: 'error'
            }));
        } finally {
            this.isPosting = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    extractErrorMessage(error) {
        if (error.body?.message) return error.body.message;
        if (typeof error.body === 'string') return error.body;
        if (error.message) return error.message;
        return 'An unknown error occurred';
    }
}
