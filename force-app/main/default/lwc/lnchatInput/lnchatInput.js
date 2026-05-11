import { LightningElement, api, track } from 'lwc';

const SUGGESTIONS = [
    { label: 'Summarize this record',    text: 'Summarize this record',                                                                                          prefill: false },
    { label: 'Meeting prep',             text: 'Meeting prep',                                                                                                   prefill: false },
    { label: 'Log a call',               text: 'Log a call with [Contact], discussed [topic], [X] minutes',                                                      prefill: true  },
    { label: 'Draft follow-up email',    text: 'Draft a follow-up email to [Contact] summarizing our call — discussed [topic], next steps: [action]',            prefill: true  },
    { label: 'What are the next steps?', text: 'What are the next steps?',                                                                                       prefill: false },
    { label: 'Open Opportunities',       text: 'Open Opportunities',                                                                                             prefill: false },
    { label: 'What are the risks?',      text: 'What are the risks?',                                                                                            prefill: false },
];

const LINE_HEIGHT = 20;
const MIN_ROWS = 1;
const MAX_ROWS = 4;
const MAX_BINARY_SIZE = 3 * 1024 * 1024; // 3 MB for images/PDFs
const MAX_TEXT_SIZE = 500 * 1024;          // 500 KB for CSV/TXT

const IMAGE_MIME_TYPES = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];

export default class LnchatInput extends LightningElement {
    @api isLoading = false;
    @track messageText = '';
    @track attachment = null;

    get suggestions() {
        return SUGGESTIONS;
    }

    get hasAttachment() {
        return this.attachment !== null;
    }

    get isSendDisabled() {
        return this.isLoading || (!this.messageText.trim() && !this.hasAttachment);
    }

    get sendButtonClass() {
        return 'send-btn' + (this.isSendDisabled ? ' send-btn-disabled' : ' send-btn-active');
    }

    get attachmentIcon() {
        if (!this.attachment) return 'utility:attach';
        const { type, name = '' } = this.attachment;
        if (type === 'image') return 'utility:image';
        if (type === 'pdf') return 'doctype:pdf';
        if (name.toLowerCase().endsWith('.csv')) return 'doctype:csv';
        return 'utility:attach';
    }

    handleInput(event) {
        this.messageText = event.target.value;
        this.autoResize(event.target);
    }

    handleKeyDown(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            if (!this.isSendDisabled) {
                this.sendMessage();
            }
        }
    }

    handleSend() {
        if (!this.isSendDisabled) {
            this.sendMessage();
        }
    }

    handleSuggestion(event) {
        const { text, prefill } = event.currentTarget.dataset;
        if (!text) return;
        this.messageText = text;
        if (prefill === 'true') {
            const textarea = this.template.querySelector('.message-textarea');
            if (textarea) {
                textarea.value = text;
                this.autoResize(textarea);
                textarea.focus();
            }
        } else {
            this.sendMessage();
        }
    }

    handleAttachmentClick() {
        const fileInput = this.template.querySelector('.file-input');
        if (fileInput) {
            fileInput.value = '';
            fileInput.click();
        }
    }

    handleFileChange(event) {
        const file = event.target.files && event.target.files[0];
        if (!file) return;

        const name = file.name;
        const mime = file.type || '';
        const isImage = IMAGE_MIME_TYPES.includes(mime);
        const isPdf = mime === 'application/pdf' || name.toLowerCase().endsWith('.pdf');
        const isText = /\.(csv|txt|json)$/i.test(name) || mime.startsWith('text/') || mime === 'application/json';
        const isWord = /\.(docx|doc)$/i.test(name);

        if (isWord) {
            this.fireAttachError('Word documents are not supported. Please save as PDF or paste the text directly.');
            return;
        }

        if (!isImage && !isPdf && !isText) {
            this.fireAttachError('Unsupported file type. Supported: images, PDF, CSV, TXT.');
            return;
        }

        const limit = isText ? MAX_TEXT_SIZE : MAX_BINARY_SIZE;
        if (file.size > limit) {
            this.fireAttachError(`File too large. Maximum size is ${Math.round(limit / (1024 * 1024))}MB.`);
            return;
        }

        if (isImage) {
            this.readAsDataURL(file, name, 'image', mime);
        } else if (isPdf) {
            this.readAsDataURL(file, name, 'pdf', 'application/pdf');
        } else {
            this.readAsText(file, name);
        }
    }

    readAsDataURL(file, name, type, mimeType) {
        const reader = new FileReader();
        reader.onload = (e) => {
            this.attachment = { type, name, mimeType, base64Data: e.target.result };
        };
        reader.onerror = () => this.fireAttachError('Failed to read file.');
        reader.readAsDataURL(file);
    }

    readAsText(file, name) {
        const reader = new FileReader();
        reader.onload = (e) => {
            let content = e.target.result;
            if (content.length > MAX_TEXT_SIZE) {
                content = content.substring(0, MAX_TEXT_SIZE) + '\n[...truncated at 500 KB...]';
            }
            this.attachment = { type: 'text', name, content };
        };
        reader.onerror = () => this.fireAttachError('Failed to read file.');
        reader.readAsText(file);
    }

    handleRemoveAttachment() {
        this.attachment = null;
    }

    sendMessage() {
        const message = this.messageText.trim();
        if (!message && !this.attachment) return;

        this.dispatchEvent(new CustomEvent('messagesend', {
            detail: { message: message || '', attachment: this.attachment },
            bubbles: true,
            composed: true
        }));

        this.messageText = '';
        this.attachment = null;
        const textarea = this.template.querySelector('.message-textarea');
        if (textarea) {
            textarea.value = '';
            textarea.style.height = 'auto';
            textarea.rows = MIN_ROWS;
        }
    }

    fireAttachError(message) {
        this.dispatchEvent(new CustomEvent('attacherror', {
            detail: { message },
            bubbles: true,
            composed: true
        }));
    }

    autoResize(el) {
        el.style.height = 'auto';
        const maxHeight = LINE_HEIGHT * MAX_ROWS + 20;
        el.style.height = Math.min(el.scrollHeight, maxHeight) + 'px';
    }

    @api
    focusInput() {
        const textarea = this.template.querySelector('.message-textarea');
        if (textarea) textarea.focus();
    }
}
