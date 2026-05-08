import { LightningElement, api, track } from 'lwc';

const FIELD_LABELS = {
    Name: 'Name',
    FirstName: 'First Name',
    LastName: 'Last Name',
    BillingStreet: 'Billing Street',
    BillingCity: 'Billing City',
    BillingState: 'Billing State/Province',
    BillingPostalCode: 'Billing Zip/Postal Code',
    BillingCountry: 'Billing Country',
    MailingStreet: 'Mailing Street',
    MailingCity: 'Mailing City',
    MailingState: 'Mailing State/Province',
    MailingPostalCode: 'Mailing Zip/Postal Code',
    Phone: 'Phone',
    Email: 'Email',
    Website: 'Website',
    Industry: 'Industry',
    Type: 'Type',
    Title: 'Title',
    Department: 'Department',
    AccountId: 'Account ID',
    ContactId: 'Contact ID',
    CloseDate: 'Close Date',
    StageName: 'Stage',
    Amount: 'Amount',
    Probability: 'Probability (%)',
    Subject: 'Subject',
    Status: 'Status',
    Priority: 'Priority',
    Origin: 'Case Origin',
    ActivityDate: 'Due Date',
    WhoId: 'Contact/Lead ID',
    WhatId: 'Related To ID',
    Description: 'Description'
};

export default class LnchatRecordActionCard extends LightningElement {
    @api operation = 'create';
    @api objectApiName = '';
    @api recordId = '';
    @api fieldsData = {};

    @track confirmed = false;
    @track cancelled = false;

    get operationLabel() {
        return this.operation === 'update' ? 'Update' : 'Create';
    }

    get operationIcon() {
        return this.operation === 'update' ? 'utility:edit' : 'utility:add';
    }

    get cardClass() {
        return 'rac-card' + (this.isDone ? ' rac-card-done' : '');
    }

    get isDone() {
        return this.confirmed || this.cancelled;
    }

    get fieldRows() {
        const src = this.fieldsData || {};
        return Object.entries(src)
            .filter(([, val]) => val !== null && val !== undefined && String(val).trim() !== '')
            .map(([name, value]) => ({
                name,
                label: FIELD_LABELS[name] || name,
                value: String(value)
            }));
    }

    handleConfirm() {
        if (this.isDone) return;
        this.confirmed = true;
        this.dispatchEvent(
            new CustomEvent('recordactionconfirm', {
                detail: {
                    operation: this.operation,
                    objectApiName: this.objectApiName,
                    recordId: this.recordId || null,
                    fields: this.fieldsData || {}
                },
                bubbles: true,
                composed: true
            })
        );
    }

    handleCancel() {
        if (this.isDone) return;
        this.cancelled = true;
        this.dispatchEvent(
            new CustomEvent('recordactioncancel', {
                bubbles: true,
                composed: true
            })
        );
    }
}
