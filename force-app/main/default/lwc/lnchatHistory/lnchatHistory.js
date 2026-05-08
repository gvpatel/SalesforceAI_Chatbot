import { LightningElement, api, track } from 'lwc';
import sendEmail from '@salesforce/apex/LNChatController.sendEmail';
import searchRecords from '@salesforce/apex/LNChatController.searchRecords';

let idCounter = 0;

const INTENT_BADGE_CLASS = {
    record_action:  'intent-badge badge-orange',
    record_summary: 'intent-badge badge-blue',
    kpi_cards:      'intent-badge badge-purple',
    chart:          'intent-badge badge-green',
    alert:          'intent-badge badge-red',
    timeline:       'intent-badge badge-grey',
    comparison:     'intent-badge badge-grey',
    table:          'intent-badge badge-grey',
    summary:        'intent-badge badge-grey'
};

export default class LnchatHistory extends LightningElement {
    @api recordId = '';
    @api isTyping = false;
    @api showIntentBadge = false;
    @track messages = [];
    @track emailAddress = '';
    @track isSendingEmail = false;

    _emailingMessageId = null;

    get isEmpty() {
        return this.messages.length === 0 && !this.isTyping;
    }

    @api
    addMessage(role, content, responseType, attachmentName) {
        const now = new Date();
        const id = ++idCounter;

        let parsedTitle = '';
        let parsedSummary = '';
        let parsedData = {};
        let parsedActions = [];
        let displayContent = content;
        let parsedResponseType = responseType || 'summary';

        if (role === 'assistant') {
            try {
                const parsed = JSON.parse(content);
                parsedTitle = parsed.title || '';
                parsedSummary = parsed.summary || '';
                parsedData = parsed.data || {};
                parsedActions = parsed.actions || [];
                parsedResponseType = parsed.responseType || 'summary';
                displayContent = parsedSummary || parsedTitle || 'Response received';
            } catch (e) {
                displayContent = content;
            }
        }

        const message = {
            id,
            role,
            content,
            responseType: parsedResponseType,
            timestamp: now,
            isUser: role === 'user',
            wrapClass: 'message-wrap ' + (role === 'user' ? 'user-wrap' : 'assistant-wrap'),
            relativeTime: this.getRelativeTime(now),
            displayContent,
            parsedTitle,
            parsedSummary,
            parsedData,
            parsedActions,
            attachmentName: attachmentName || null,
            hasAttachment: !!attachmentName,
            intentBadgeClass: INTENT_BADGE_CLASS[parsedResponseType] || 'intent-badge badge-grey',
            showEmailOverlay: false
        };

        this.messages = [...this.messages, message];
        this.scrollToBottom();
        this.startRelativeTimeRefresh();
    }

    @api
    clearMessages() {
        this.messages = [];
        idCounter = 0;
        this._emailingMessageId = null;
        this.emailAddress = '';
    }

    // ─── Email handlers ───────────────────────────────────────────────────────

    handleEmailIconClick(event) {
        const msgId = parseInt(event.currentTarget.dataset.msgId, 10);
        const alreadyOpen = this._emailingMessageId === msgId;
        this.messages = this.messages.map(m => ({
            ...m,
            showEmailOverlay: !alreadyOpen && m.id === msgId
        }));
        this._emailingMessageId = alreadyOpen ? null : msgId;
        this.emailAddress = '';
    }

    handleEmailAddressChange(event) {
        this.emailAddress = event.target.value;
    }

    handleEmailKeydown(event) {
        if (event.key === 'Enter') this.handleEmailSend(event);
    }

    handleEmailCancel(event) {
        const msgId = parseInt(event.currentTarget.dataset.msgId, 10);
        this.messages = this.messages.map(m => ({
            ...m,
            showEmailOverlay: m.id === msgId ? false : m.showEmailOverlay
        }));
        this._emailingMessageId = null;
        this.emailAddress = '';
    }

    async handleEmailSend(event) {
        const msgId = parseInt(event.currentTarget.dataset.msgId, 10);
        const toAddress = this.emailAddress.trim();
        if (!toAddress || !toAddress.includes('@')) return;
        const msg = this.messages.find(m => m.id === msgId);
        if (!msg) return;

        this.isSendingEmail = true;
        try {
            const subject = msg.parsedTitle || 'AI Assistant Response';
            let htmlBody;

            if (msg.responseType === 'record_list') {
                const d = msg.parsedData || {};
                const result = await searchRecords({
                    objectApiName: d.objectApiName || 'Account',
                    filtersJson:   JSON.stringify(d.filters  || []),
                    columnsJson:   JSON.stringify(d.columns  || []),
                    orderByField:  d.orderBy   || null,
                    orderDesc:     d.orderDesc || false,
                    limitRows:     d.limitRows || 20
                });
                htmlBody = this.buildRecordListEmailHtml(msg, result);
            } else {
                htmlBody = this.buildEmailHtml(msg);
            }

            await sendEmail({ toAddress, subject, htmlBody });
            this.messages = this.messages.map(m => ({ ...m, showEmailOverlay: false }));
            this._emailingMessageId = null;
            this.emailAddress = '';
            this.dispatchEvent(new CustomEvent('showtoast', {
                bubbles: true, composed: true,
                detail: { title: 'Email sent', message: `Sent to ${toAddress}`, variant: 'success' }
            }));
        } catch (e) {
            this.dispatchEvent(new CustomEvent('showtoast', {
                bubbles: true, composed: true,
                detail: { title: 'Email failed', message: (e && e.body && e.body.message) ? e.body.message : 'Could not send email.', variant: 'error' }
            }));
        } finally {
            this.isSendingEmail = false;
        }
    }

    // ─── HTML email builders ─────────────────────────────────────────────────

    buildEmailHtml(msg) {
        const d   = msg.parsedData || {};
        const title   = msg.parsedTitle   || 'AI Assistant Response';
        const summary = msg.parsedSummary || '';
        const type    = msg.responseType;

        const ts   = 'width:100%;border-collapse:collapse;margin:8px 0;';
        const ths  = 'background:#f3f4f5;padding:8px;text-align:left;font-size:12px;color:#706e6b;border-bottom:2px solid #dddbda;';
        const tds  = 'padding:8px;border-bottom:1px solid #f3f4f5;font-size:13px;color:#032D60;';
        const foot = '<hr style="border:none;border-top:1px solid #dddbda;margin:20px 0 10px"/><p style="font-size:11px;color:#aaa;margin:0">Sent from Salesforce AI Assistant</p>';

        let b = `<div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;color:#032D60">`;
        b += `<h2 style="font-size:20px;margin:0 0 8px;color:#032D60">${this.esc(title)}</h2>`;
        if (summary) b += `<p style="font-size:14px;color:#444;margin:0 0 16px;line-height:1.5">${this.esc(summary)}</p>`;

        if (type === 'record_summary') {
            const hdr  = d.header   || {};
            const kpis = d.kpis     || [];
            const secs = d.sections || [];
            if (hdr.subtitle) b += `<p style="font-size:13px;color:#706e6b;margin:0 0 12px">${this.esc(hdr.subtitle)}</p>`;
            if (kpis.length) {
                b += '<p style="font-size:12px;color:#706e6b;font-weight:600;margin:0 0 4px">KEY METRICS</p><div style="margin:0 0 16px">';
                kpis.forEach(k => {
                    b += `<span style="display:inline-block;margin:2px 6px 2px 0;padding:3px 10px;background:#f3f4f5;border-radius:12px;font-size:12px;color:#032D60"><strong>${this.esc(k.label)}:</strong> ${this.esc(String(k.value))}${k.sub ? ' (' + this.esc(k.sub) + ')' : ''}</span>`;
                });
                b += '</div>';
            }
            secs.forEach(s => {
                const items = s.items || [];
                if (!items.length) return;
                b += `<h3 style="font-size:13px;color:#706e6b;font-weight:600;margin:16px 0 4px;text-transform:uppercase">${this.esc(s.title || '')}</h3>`;
                b += `<table style="${ts}"><thead><tr><th style="${ths}">Name</th><th style="${ths}">Detail</th><th style="${ths}">Date</th><th style="${ths}">Amount</th></tr></thead><tbody>`;
                items.forEach(i => {
                    b += `<tr><td style="${tds}">${this.esc(i.name || '')}</td><td style="${tds}">${this.esc(i.subtitle || '')}</td><td style="${tds}">${this.esc(i.date || '')}</td><td style="${tds}">${this.esc(i.amount || '')}</td></tr>`;
                });
                b += '</tbody></table>';
            });

        } else if (type === 'kpi_cards') {
            b += `<table style="${ts}"><thead><tr><th style="${ths}">Metric</th><th style="${ths}">Value</th><th style="${ths}">Trend</th></tr></thead><tbody>`;
            (d.cards || []).forEach(c => {
                b += `<tr><td style="${tds}">${this.esc(c.label || '')}</td><td style="${tds}">${this.esc(String(c.value || ''))} ${this.esc(c.unit || '')}</td><td style="${tds}">${this.esc(c.trend || '')}</td></tr>`;
            });
            b += '</tbody></table>';

        } else if (type === 'alert') {
            const sevColors = { critical: '#ba0517', warning: '#a85500', info: '#0176d3', success: '#2e844a' };
            const sevBg     = { critical: '#fde8e8', warning: '#fef0e0', info: '#e8f3fe', success: '#e8f7ee' };
            const sev = d.severity || 'info';
            b += `<div style="border-left:4px solid ${sevColors[sev]||'#0176d3'};background:${sevBg[sev]||'#e8f3fe'};padding:12px 16px;margin:8px 0;border-radius:4px">`;
            b += `<p style="font-weight:600;color:${sevColors[sev]||'#0176d3'};margin:0 0 6px">${this.esc(d.alertTitle || '')}</p>`;
            b += `<p style="font-size:13px;margin:0 0 8px;color:#333">${this.esc(d.message || '')}</p>`;
            if (d.details && d.details.length) {
                b += '<ul style="margin:0;padding-left:16px">';
                d.details.forEach(det => { b += `<li style="font-size:12px;color:#333;margin:2px 0">${this.esc(det)}</li>`; });
                b += '</ul>';
            }
            b += '</div>';

        } else if (type === 'summary') {
            (d.sections || []).forEach(s => {
                if (s.heading) b += `<h3 style="font-size:14px;color:#032D60;margin:12px 0 4px">${this.esc(s.heading)}</h3>`;
                b += `<p style="font-size:13px;color:#333;margin:0 0 12px;line-height:1.5">${this.esc(s.body || '')}</p>`;
            });

        } else if (type === 'timeline') {
            b += `<table style="${ts}"><thead><tr><th style="${ths}">Date</th><th style="${ths}">Event</th><th style="${ths}">Status</th></tr></thead><tbody>`;
            (d.events || []).forEach(e => {
                b += `<tr><td style="${tds}">${this.esc(e.date || '')}</td><td style="${tds}"><strong>${this.esc(e.title || '')}</strong><br/><span style="color:#706e6b;font-size:12px">${this.esc(e.description || '')}</span></td><td style="${tds}">${this.esc(e.status || '')}</td></tr>`;
            });
            b += '</tbody></table>';

        } else if (type === 'comparison') {
            const cols = d.columns || ['Field', 'Salesforce', 'External'];
            b += `<table style="${ts}"><thead><tr>${cols.map(c => `<th style="${ths}">${this.esc(c)}</th>`).join('')}</tr></thead><tbody>`;
            (d.rows || []).forEach(r => {
                const hi = r.isDifferent ? 'background:#fff8e1;' : '';
                b += `<tr style="${hi}"><td style="${tds}">${this.esc(r.field || '')}</td><td style="${tds}">${this.esc(r.salesforceValue || '')}</td><td style="${tds}">${this.esc(r.externalValue || '')}</td></tr>`;
            });
            b += '</tbody></table>';

        } else if (type === 'table') {
            const cols = d.columns || [];
            b += `<table style="${ts}"><thead><tr>${cols.map(c => `<th style="${ths}">${this.esc(c)}</th>`).join('')}</tr></thead><tbody>`;
            (d.rows || []).forEach(r => {
                b += `<tr>${r.map(v => `<td style="${tds}">${this.esc(String(v || ''))}</td>`).join('')}</tr>`;
            });
            b += '</tbody></table>';
        }

        b += foot + '</div>';
        return b;
    }

    buildRecordListEmailHtml(msg, result) {
        const title   = msg.parsedTitle   || 'Search Results';
        const summary = msg.parsedSummary || '';
        const cols    = (result.columns || []).filter(c => c !== 'Id');
        const rows    = result.rows || [];

        const ts  = 'width:100%;border-collapse:collapse;margin:8px 0;';
        const ths = 'background:#f3f4f5;padding:8px;text-align:left;font-size:12px;color:#706e6b;border-bottom:2px solid #dddbda;';
        const tds = 'padding:8px;border-bottom:1px solid #f3f4f5;font-size:13px;color:#032D60;';
        const foot = '<hr style="border:none;border-top:1px solid #dddbda;margin:20px 0 10px"/><p style="font-size:11px;color:#aaa;margin:0">Sent from Salesforce AI Assistant</p>';

        let b = `<div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;color:#032D60">`;
        b += `<h2 style="font-size:20px;margin:0 0 8px;color:#032D60">${this.esc(title)}</h2>`;
        if (summary) b += `<p style="font-size:14px;color:#444;margin:0 0 8px;line-height:1.5">${this.esc(summary)}</p>`;
        b += `<p style="font-size:12px;color:#706e6b;margin:0 0 12px">${result.count || 0} records</p>`;

        if (rows.length) {
            b += `<table style="${ts}"><thead><tr>${cols.map(c => `<th style="${ths}">${this.esc(this.formatColLabel(c))}</th>`).join('')}</tr></thead><tbody>`;
            rows.forEach(row => {
                b += '<tr>' + cols.map(col => {
                    const key = col.includes('.') ? col.replace('.', '_') : col;
                    const val = row[key] != null ? String(row[key]) : '';
                    return `<td style="${tds}">${this.esc(val)}</td>`;
                }).join('') + '</tr>';
            });
            b += '</tbody></table>';
        } else {
            b += '<p style="font-size:13px;color:#706e6b;font-style:italic">No records found.</p>';
        }

        b += foot + '</div>';
        return b;
    }

    formatColLabel(fieldName) {
        return fieldName
            .replace(/__c$/i, '')
            .replace(/__r$/i, '')
            .replace(/([a-z])([A-Z])/g, '$1 $2')
            .replace(/_/g, ' ');
    }

    esc(str) {
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    // ─── Scroll & time ────────────────────────────────────────────────────────

    scrollToBottom() {
        requestAnimationFrame(() => {
            const anchor = this.template.querySelector('.scroll-anchor');
            if (anchor) {
                anchor.scrollIntoView({ behavior: 'smooth', block: 'end' });
            }
        });
    }

    getRelativeTime(date) {
        const now = new Date();
        const diffMs = now - date;
        const diffSec = Math.floor(diffMs / 1000);
        const diffMin = Math.floor(diffSec / 60);
        const diffHr = Math.floor(diffMin / 60);

        if (diffSec < 10) return 'just now';
        if (diffSec < 60) return diffSec + 's ago';
        if (diffMin < 60) return diffMin + 'min ago';
        if (diffHr < 24) return diffHr + 'h ago';
        return date.toLocaleDateString();
    }

    startRelativeTimeRefresh() {
        if (this._refreshTimer) return;
        this._refreshTimer = setInterval(() => {
            this.messages = this.messages.map((msg) => ({
                ...msg,
                relativeTime: this.getRelativeTime(msg.timestamp)
            }));
        }, 30000);
    }

    disconnectedCallback() {
        if (this._refreshTimer) {
            clearInterval(this._refreshTimer);
            this._refreshTimer = null;
        }
    }
}
