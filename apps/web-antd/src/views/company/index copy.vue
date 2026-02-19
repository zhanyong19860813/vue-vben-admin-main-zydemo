<script setup lang="ts">
import QueryTable from '#/components/QueryTable/index.vue';
import { companySchema } from './company.schema';
</script>

<template>
  <QueryTable :schema="companySchema" />
</template>
